import AppKit
import Foundation

@MainActor
final class XcodeClient {
    private var activeProcess: Process?
    private var launchedMacProcess: Process?

    func loadConfiguration(
        for project: XcodeProject,
        savedScheme: String?,
        savedDestinationID: String?
    ) async throws -> ProjectConfiguration {
        let schemes = try await schemes(for: project)
        guard !schemes.isEmpty else { throw RunError.noSchemes }

        let selectedScheme: String
        if let savedScheme, schemes.contains(savedScheme) {
            selectedScheme = savedScheme
        } else {
            selectedScheme = XcodeOutputParser.preferredScheme(in: project, availableSchemes: schemes) ?? schemes[0]
        }

        let destinations = try await destinations(for: project, scheme: selectedScheme)
        let selectedDestination = await preferredDestination(
            in: destinations,
            savedDestinationID: savedDestinationID
        )

        return ProjectConfiguration(
            schemes: schemes,
            destinations: destinations,
            selectedScheme: selectedScheme,
            selectedDestination: selectedDestination
        )
    }

    func schemes(for project: XcodeProject) async throws -> [String] {
        let listResult = try await xcodebuild(["-list", "-json"] + containerArguments(for: project))
        let schemes = try XcodeOutputParser.schemes(from: listResult.standardOutput)
        guard !schemes.isEmpty else { throw RunError.noSchemes }
        return schemes
    }

    func preferredDestination(
        in destinations: [RunDestination],
        savedDestinationID: String?
    ) async -> RunDestination? {
        let bootedIDs = await bootedSimulatorIDs()
        return destinations.first { $0.id == savedDestinationID }
            ?? XcodeOutputParser.preferredDestination(destinations, bootedSimulatorIDs: bootedIDs)
    }

    func destinations(for project: XcodeProject, scheme: String) async throws -> [RunDestination] {
        let result = try await xcodebuild(["-showdestinations", "-scheme", scheme] + containerArguments(for: project))
        let destinations = XcodeOutputParser.destinations(from: result.combinedOutput)
        guard !destinations.isEmpty else { throw RunError.noDestinations }
        let metadataByIdentifier = await deviceMetadataByIdentifier()
        return destinations.map { destination in
            if destination.isMac, destination.osVersion == nil {
                return destination.addingMetadata(
                    osVersion: hostOperatingSystemVersion,
                    connectionKind: .local
                )
            }
            guard let identifier = destination.identifier,
                  let metadata = metadataByIdentifier[identifier] else { return destination }
            return destination.addingMetadata(
                osVersion: metadata.osVersion,
                connectionKind: metadata.connectionKind
            )
        }
    }

    func buildAndLaunch(project: XcodeProject, scheme: String, destination: RunDestination) async throws -> LaunchContext {
        guard destination.isRunnable else { throw RunError.noRunnableDestination }
        let schemeConfiguration = try SchemeRunConfigurationParser.configuration(in: project, scheme: scheme)
        switch schemeConfiguration.runnableKind {
        case .generated, .buildableProduct:
            break
        case .unsupported(let kind):
            throw RunError.unsupportedRunAction(kind)
        }
        guard schemeConfiguration.launchStyle == "0" else {
            throw RunError.unsupportedRunAction("wait for executable launch style")
        }
        let destinationArguments = [
            "-scheme", scheme,
            "-destination", destination.commandSpecifier,
            "-configuration", schemeConfiguration.buildConfiguration,
        ] + SchemeLaunchPlan.sanitizerArguments(for: schemeConfiguration)
        _ = try await xcodebuild(containerArguments(for: project) + destinationArguments + ["build"])
        try Task.checkCancellation()

        let settingsResult = try await xcodebuild(
            containerArguments(for: project) + destinationArguments + ["-showBuildSettings", "-json"]
        )
        let allBuildSettings = try XcodeOutputParser.buildSettings(from: settingsResult.standardOutput)
        let settings = try XcodeOutputParser.appBuildSettings(
            from: settingsResult.standardOutput,
            targetName: schemeConfiguration.executableTargetName,
            productName: schemeConfiguration.executableProductName
        )
        let launchConfiguration = SchemeLaunchPlan.resolve(
            schemeConfiguration,
            buildSettings: settings.values
        )
        try Task.checkCancellation()

        let preActions = preparedActions(
            launchConfiguration.preActions,
            allBuildSettings: allBuildSettings,
            fallbackSettings: settings.values,
            project: project
        )
        let postActions = preparedActions(
            launchConfiguration.postActions,
            allBuildSettings: allBuildSettings,
            fallbackSettings: settings.values,
            project: project
        )
        var deviceProcessIdentifier: Int?
        do {
            for action in preActions {
                _ = try await run(action)
                try Task.checkCancellation()
            }

            if destination.isMac {
                deviceProcessIdentifier = try await launchMacApplication(
                    settings: settings,
                    configuration: launchConfiguration
                )
            } else if let identifier = destination.identifier {
                if destination.isSimulator {
                    _ = try? await developerCommand("simctl", arguments: ["boot", identifier])
                    _ = try await developerCommand("simctl", arguments: ["bootstatus", identifier, "-b"])
                }
                _ = try await developerCommand(
                    "devicectl",
                    arguments: SchemeLaunchPlan.devicectlInstallArguments(
                        identifier: identifier,
                        appPath: settings.path.path
                    )
                )
                let launchResult = try await developerCommand(
                    "devicectl",
                    arguments: SchemeLaunchPlan.devicectlLaunchArguments(
                        identifier: identifier,
                        bundleIdentifier: settings.bundleIdentifier,
                        configuration: launchConfiguration
                    ),
                    environment: SchemeLaunchPlan.devicectlEnvironment(for: launchConfiguration)
                )
                deviceProcessIdentifier = XcodeOutputParser.deviceProcessIdentifier(from: launchResult.standardOutput)
            }
        } catch {
            for action in postActions {
                _ = try? await run(action)
            }
            throw error
        }

        return LaunchContext(
            bundleIdentifier: settings.bundleIdentifier,
            executableName: settings.executableName,
            destination: destination,
            deviceProcessIdentifier: deviceProcessIdentifier,
            postActions: postActions
        )
    }

    func stop(_ context: LaunchContext?) async throws {
        cancelActiveCommand()
        guard let context else { return }

        if context.destination.isMac {
            launchedMacProcess?.terminate()
            launchedMacProcess = nil
            let applications = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier)
            applications.forEach { $0.terminate() }
        } else if context.destination.isSimulator, let identifier = context.destination.identifier {
            _ = try? await developerCommand(
                "simctl",
                arguments: SchemeLaunchPlan.simulatorTerminateArguments(
                    identifier: identifier,
                    bundleIdentifier: context.bundleIdentifier
                )
            )
        } else if let identifier = context.destination.identifier,
                  let processIdentifier = context.deviceProcessIdentifier {
            _ = try? await developerCommand(
                "devicectl",
                arguments: SchemeLaunchPlan.devicectlTerminateArguments(
                    identifier: identifier,
                    processIdentifier: processIdentifier
                )
            )
        }

        for action in context.postActions {
            _ = try await run(action)
        }
    }

    func cancelActiveCommand() {
        activeProcess?.terminate()
        activeProcess = nil
    }

    private func containerArguments(for project: XcodeProject) -> [String] {
        [project.kind.commandFlag, project.url.path]
    }

    private func bootedSimulatorIDs() async -> Set<String> {
        guard let result = try? await developerCommand("simctl", arguments: ["list", "devices", "booted", "--json"]),
              let object = try? JSONSerialization.jsonObject(with: result.standardOutput),
              let root = object as? [String: Any],
              let runtimes = root["devices"] as? [String: [[String: Any]]]
        else { return [] }

        return Set(runtimes.values.flatMap { devices in
            devices.compactMap { $0["udid"] as? String }
        })
    }

    private func deviceMetadataByIdentifier() async -> [String: DeviceMetadata] {
        guard let result = try? await developerCommand(
            "devicectl",
            arguments: ["list", "devices", "--json-output", "-"]
        ),
        let object = try? JSONSerialization.jsonObject(with: result.standardOutput),
        let root = object as? [String: Any],
        let resultObject = root["result"] as? [String: Any],
        let devices = resultObject["devices"] as? [[String: Any]]
        else { return [:] }

        return devices.reduce(into: [String: DeviceMetadata]()) { metadata, device in
            let properties = device["properties"] as? [String: Any]
            let hardware = properties?["hardware"] as? [String: Any]
            let software = properties?["software"] as? [String: Any]
            let connection = properties?["connection"] as? [String: Any]
            let legacyHardware = device["hardwareProperties"] as? [String: Any]
            let legacyDevice = device["deviceProperties"] as? [String: Any]
            let legacyConnection = device["connectionProperties"] as? [String: Any]

            guard let identifier = (hardware?["udid"] ?? legacyHardware?["udid"]) as? String else { return }
            let versionObject = software?["osVersionNumber"] as? [String: Any]
            let osVersion = (versionObject?["stringValue"] as? String)
                ?? (legacyDevice?["osVersionNumber"] as? String)
            let transport = (connection?["transportType"] as? String)
                ?? (legacyConnection?["transportType"] as? String)
            metadata[identifier] = DeviceMetadata(
                osVersion: osVersion,
                connectionKind: connectionKind(for: transport)
            )
        }
    }

    private func connectionKind(for transport: String?) -> DestinationConnectionKind? {
        switch transport?.lowercased() {
        case "localnetwork", "network", "wifi", "wireless": .wireless
        case "cloud": .cloud
        case .some: .local
        case nil: nil
        }
    }

    private var hostOperatingSystemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    private func xcodebuild(_ arguments: [String]) async throws -> CommandResult {
        let executable = developerDirectory
            .appendingPathComponent("usr/bin/xcodebuild")
            .path
        return try await command(executable: executable, arguments: arguments)
    }

    private func developerCommand(
        _ tool: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> CommandResult {
        try await command(
            executable: "/usr/bin/xcrun",
            arguments: [tool] + arguments,
            environment: environment.merging(["DEVELOPER_DIR": developerDirectory.path]) { current, _ in current }
        )
    }

    private func preparedActions(
        _ actions: [SchemeExecutionAction],
        allBuildSettings: [TargetBuildSettings],
        fallbackSettings: [String: String],
        project: XcodeProject
    ) -> [PreparedSchemeExecutionAction] {
        actions.map { action in
            let settings = allBuildSettings.first { candidate in
                action.targetName == candidate.targetName || action.targetName == candidate.values["TARGET_NAME"]
            }?.values ?? fallbackSettings
            let environment = ProcessInfo.processInfo.environment.merging(settings) { _, setting in setting }
            let workingDirectory = settings["SRCROOT"].map(URL.init(fileURLWithPath:))
                ?? project.url.deletingLastPathComponent()
            return PreparedSchemeExecutionAction(
                action: action,
                environment: environment,
                workingDirectory: workingDirectory
            )
        }
    }

    private func run(_ action: PreparedSchemeExecutionAction) async throws -> CommandResult {
        try await command(
            executable: "/bin/sh",
            arguments: ["-c", action.action.script],
            environment: action.environment,
            currentDirectory: action.workingDirectory
        )
    }

    private func launchMacApplication(
        settings: AppBuildSettings,
        configuration: ResolvedSchemeRunConfiguration
    ) async throws -> Int? {
        if let workingDirectory = configuration.workingDirectory {
            let process = Process()
            process.executableURL = settings.path
                .appendingPathComponent("Contents/MacOS")
                .appendingPathComponent(settings.executableName)
            process.arguments = configuration.arguments
            process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, scheme in scheme }
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw RunError.commandFailed(error.localizedDescription)
            }
            launchedMacProcess = process
            return Int(process.processIdentifier)
        }

        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.arguments = configuration.arguments
        openConfiguration.environment = configuration.environment
        openConfiguration.createsNewApplicationInstance = true
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: settings.path, configuration: openConfiguration) { application, error in
                if let error {
                    continuation.resume(throwing: RunError.commandFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: application.map { Int($0.processIdentifier) })
                }
            }
        }
    }

    private var developerDirectory: URL {
        let selected = ProcessInfo.processInfo.environment["DEVELOPER_DIR"].map(URL.init(fileURLWithPath:))
        let discovered = ((try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? [])
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
            .sorted()
            .map { URL(fileURLWithPath: "/Applications/\($0)/Contents/Developer") }
        let candidates = [
            selected,
            URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer"),
            URL(fileURLWithPath: "/Applications/Xcode-beta.app/Contents/Developer"),
        ].compactMap { $0 } + discovered

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent("usr/bin/xcodebuild").path)
        } ?? URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
    }

    private func command(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil
    ) async throws -> CommandResult {
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.currentDirectoryURL = currentDirectory
        activeProcess = process

        do {
            try process.run()
        } catch {
            activeProcess = nil
            throw RunError.commandFailed(error.localizedDescription)
        }

        let status = await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
        }
        activeProcess = nil
        try? outputHandle.synchronize()
        try? errorHandle.synchronize()
        let standardOutput = (try? Data(contentsOf: outputURL)) ?? Data()
        let standardError = (try? Data(contentsOf: errorURL)) ?? Data()
        let result = CommandResult(standardOutput: standardOutput, standardError: standardError)

        guard status == 0 else {
            let message = result.combinedOutput
                .split(separator: "\n")
                .suffix(14)
                .joined(separator: "\n")
            throw RunError.commandFailed(message.isEmpty ? "The command failed with status \(status)." : message)
        }
        return result
    }
}

private struct DeviceMetadata {
    let osVersion: String?
    let connectionKind: DestinationConnectionKind?
}

private struct CommandResult {
    let standardOutput: Data
    let standardError: Data

    var combinedOutput: String {
        [standardOutput, standardError]
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}

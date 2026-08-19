import AppKit
import Foundation

@MainActor
final class XcodeClient {
    private var activeProcess: Process?

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
        return destinations
    }

    func buildAndLaunch(project: XcodeProject, scheme: String, destination: RunDestination) async throws -> LaunchContext {
        guard destination.isRunnable else { throw RunError.noRunnableDestination }
        let destinationArguments = ["-scheme", scheme, "-destination", destination.commandSpecifier, "-configuration", "Debug"]
        _ = try await xcodebuild(containerArguments(for: project) + destinationArguments + ["build"])
        try Task.checkCancellation()

        let settingsResult = try await xcodebuild(
            containerArguments(for: project) + destinationArguments + ["-showBuildSettings", "-json"]
        )
        let settings = try XcodeOutputParser.appBuildSettings(from: settingsResult.standardOutput)
        try Task.checkCancellation()

        var deviceProcessIdentifier: Int?
        if destination.isMac {
            _ = try await command(executable: "/usr/bin/open", arguments: ["-n", settings.path.path])
        } else if destination.isSimulator, let identifier = destination.identifier {
            _ = try? await developerCommand("simctl", arguments: ["boot", identifier])
            _ = try await developerCommand("simctl", arguments: ["bootstatus", identifier, "-b"])
            _ = try await developerCommand("simctl", arguments: ["install", identifier, settings.path.path])
            _ = try await developerCommand("simctl", arguments: ["launch", identifier, settings.bundleIdentifier])
        } else if let identifier = destination.identifier {
            _ = try await developerCommand("devicectl", arguments: [
                "device", "install", "app", "--device", identifier, settings.path.path,
            ])
            let launchResult = try await developerCommand("devicectl", arguments: [
                "device", "process", "launch", "--device", identifier,
                "--terminate-existing", "--json-output", "-", settings.bundleIdentifier,
            ])
            deviceProcessIdentifier = XcodeOutputParser.deviceProcessIdentifier(from: launchResult.standardOutput)
        }

        return LaunchContext(
            bundleIdentifier: settings.bundleIdentifier,
            executableName: settings.executableName,
            destination: destination,
            deviceProcessIdentifier: deviceProcessIdentifier
        )
    }

    func stop(_ context: LaunchContext?) async {
        cancelActiveCommand()
        guard let context else { return }

        if context.destination.isMac {
            let applications = NSRunningApplication.runningApplications(withBundleIdentifier: context.bundleIdentifier)
            applications.forEach { $0.terminate() }
        } else if context.destination.isSimulator, let identifier = context.destination.identifier {
            _ = try? await developerCommand("simctl", arguments: [
                "terminate", identifier, context.bundleIdentifier,
            ])
        } else if let identifier = context.destination.identifier,
                  let processIdentifier = context.deviceProcessIdentifier {
            _ = try? await developerCommand("devicectl", arguments: [
                "device", "process", "terminate", "--device", identifier,
                "--pid", String(processIdentifier),
            ])
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

    private func xcodebuild(_ arguments: [String]) async throws -> CommandResult {
        let executable = developerDirectory
            .appendingPathComponent("usr/bin/xcodebuild")
            .path
        return try await command(executable: executable, arguments: arguments)
    }

    private func developerCommand(_ tool: String, arguments: [String]) async throws -> CommandResult {
        try await command(
            executable: "/usr/bin/xcrun",
            arguments: [tool] + arguments,
            environment: ["DEVELOPER_DIR": developerDirectory.path]
        )
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
        environment: [String: String] = [:]
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

private struct CommandResult {
    let standardOutput: Data
    let standardError: Data

    var combinedOutput: String {
        [standardOutput, standardError]
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}

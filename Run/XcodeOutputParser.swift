import Foundation

enum XcodeOutputParser {
    static func localSchemes(in project: XcodeProject) -> [String] {
        localSchemeDescriptors(in: project).map(\.name)
    }

    static func localSchemeDescriptors(in project: XcodeProject) -> [SchemeDescriptor] {
        guard let enumerator = FileManager.default.enumerator(
            at: project.url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var descriptors: [String: SchemeDescriptor] = [:]
        for case let fileURL as URL in enumerator
        where fileURL.pathExtension == "xcscheme" && fileURL.path.contains("/xcschemes/") {
            let name = fileURL.deletingPathExtension().lastPathComponent
            descriptors[name] = schemeDescriptor(name: name, fileURL: fileURL)
        }
        return descriptors.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func userSchemes(discovered: [String], local: [String]) -> [String] {
        guard !local.isEmpty else { return discovered }
        let discoveredSet = Set(discovered)
        return local.filter(discoveredSet.contains)
    }

    static func schemes(from data: Data) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard
            let root = object as? [String: Any],
            let container = (root["project"] ?? root["workspace"]) as? [String: Any],
            let schemes = container["schemes"] as? [String]
        else {
            throw RunError.noSchemes
        }
        return schemes
    }

    static func schemeDescriptor(name: String, fromBuildSettings data: Data) throws -> SchemeDescriptor {
        let targets = try buildSettings(from: data)
        let preferred = targets.first { target in
            target.targetName == name || target.values["TARGET_NAME"] == name
        } ?? targets.first { target in
            guard let productName = target.values["FULL_PRODUCT_NAME"] else { return false }
            return URL(fileURLWithPath: productName).deletingPathExtension().lastPathComponent == name
        } ?? targets.first { $0.values["WRAPPER_EXTENSION"] == "app" }
            ?? targets.first
        let productName = preferred?.values["FULL_PRODUCT_NAME"]
        return SchemeDescriptor(
            name: name,
            productName: productName,
            productKind: productKind(for: productName)
        )
    }

    static func destinations(from output: String) -> [RunDestination] {
        output.split(separator: "\n").compactMap { line in
            guard let opening = line.firstIndex(of: "{"), let closing = line.lastIndex(of: "}") else {
                return nil
            }

            let body = line[line.index(after: opening)..<closing]
            let fields = body.split(separator: ",").reduce(into: [String: String]()) { result, field in
                let pair = field.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if pair.count == 2 {
                    result[pair[0]] = pair[1]
                }
            }

            guard let platform = fields["platform"], let name = fields["name"] else { return nil }
            let isIOSAppOnMac = platform == "macOS"
                && fields["variant"]?.localizedCaseInsensitiveContains("Designed for") == true
            guard !isIOSAppOnMac else { return nil }
            let identifier = fields["id"].flatMap { $0 == "dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder" ? nil : $0 }
            let error = fields["error"]
            let generic = identifier == nil || identifier?.localizedCaseInsensitiveContains("placeholder") == true || name.hasPrefix("Any ")
            return RunDestination(
                platform: platform,
                name: name,
                identifier: identifier,
                isGeneric: generic,
                osVersion: fields["OS"],
                availabilityError: error
            )
        }
    }

    static func runningDestinationGroups(
        from destinations: [RunDestination],
        recentDestinationIDs: [String]
    ) -> [RunDestinationGroup] {
        let recent = recentDestinationIDs.compactMap { identifier in
            destinations.first { $0.id == identifier && $0.isRunnable }
        }
        let recentSet = Set(recent.map(\.id))
        let runnable = destinations.filter { $0.isRunnable && !recentSet.contains($0.id) }
        let devices = runnable.filter { !$0.isSimulator }
        let simulators = runnable.filter(\.isSimulator)

        var groups: [RunDestinationGroup] = []
        if !recent.isEmpty { groups.append(RunDestinationGroup(name: "Recent", destinations: recent)) }
        if !devices.isEmpty { groups.append(RunDestinationGroup(name: "Devices", destinations: devices)) }
        if !simulators.isEmpty { groups.append(RunDestinationGroup(name: "Simulators", destinations: simulators)) }
        return groups
    }

    static func appBuildSettings(
        from data: Data,
        targetName: String? = nil,
        productName: String? = nil
    ) throws -> AppBuildSettings {
        let targets = try buildSettings(from: data)
        let apps = targets.compactMap { target -> AppBuildSettings? in
            let settings = target.values
            guard
                settings["WRAPPER_EXTENSION"] == "app",
                let directory = settings["TARGET_BUILD_DIR"],
                let product = settings["FULL_PRODUCT_NAME"],
                let bundleIdentifier = settings["PRODUCT_BUNDLE_IDENTIFIER"],
                let executableName = settings["EXECUTABLE_NAME"]
            else { return nil }
            return AppBuildSettings(
                path: URL(fileURLWithPath: directory).appendingPathComponent(product),
                bundleIdentifier: bundleIdentifier,
                executableName: executableName,
                targetName: target.targetName,
                values: settings
            )
        }

        if let match = apps.first(where: { app in
            let matchesTarget = targetName == nil || app.targetName == targetName
                || app.values["TARGET_NAME"] == targetName
            let matchesProduct = productName == nil || app.values["FULL_PRODUCT_NAME"] == productName
            return matchesTarget && matchesProduct
        }) {
            return match
        }
        throw RunError.appProductNotFound
    }

    static func buildSettings(from data: Data) throws -> [TargetBuildSettings] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let targets = object as? [[String: Any]] else { throw RunError.appProductNotFound }
        return targets.compactMap { target in
            guard let rawSettings = target["buildSettings"] as? [String: Any] else { return nil }
            let settings = rawSettings.reduce(into: [String: String]()) { result, pair in
                if let value = pair.value as? String {
                    result[pair.key] = value
                } else if pair.value is NSNumber {
                    result[pair.key] = String(describing: pair.value)
                }
            }
            return TargetBuildSettings(targetName: target["target"] as? String, values: settings)
        }
    }

    static func deviceProcessIdentifier(from data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findInteger(named: "processIdentifier", in: object)
    }

    static func preferredScheme(in project: XcodeProject, availableSchemes: [String]) -> String? {
        guard !availableSchemes.isEmpty else { return nil }
        let root = project.url.appendingPathComponent("xcuserdata")
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return availableSchemes.first
        }

        var ordered: [(name: String, order: Int)] = []
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "xcschememanagement.plist" {
            guard
                let data = try? Data(contentsOf: fileURL),
                let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
                let root = propertyList as? [String: Any],
                let states = root["SchemeUserState"] as? [String: [String: Any]]
            else { continue }

            for (key, value) in states {
                let name = key
                    .replacingOccurrences(of: "_^#shared#^_", with: "")
                    .replacingOccurrences(of: ".xcscheme", with: "")
                if availableSchemes.contains(name), value["isShown"] as? Bool != false {
                    ordered.append((name, value["orderHint"] as? Int ?? .max))
                }
            }
        }

        return ordered.min { $0.order < $1.order }?.name ?? availableSchemes.first
    }

    static func preferredDestination(_ destinations: [RunDestination], bootedSimulatorIDs: Set<String>) -> RunDestination? {
        let runnable = destinations.filter(\.isRunnable)
        return runnable.first { destination in
            destination.identifier.map(bootedSimulatorIDs.contains) == true
        } ?? runnable.first
    }

    private static func findInteger(named key: String, in object: Any) -> Int? {
        if let dictionary = object as? [String: Any] {
            if let value = dictionary[key] as? Int { return value }
            for value in dictionary.values {
                if let match = findInteger(named: key, in: value) { return match }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findInteger(named: key, in: value) { return match }
            }
        }
        return nil
    }

    private static func schemeDescriptor(name: String, fileURL: URL) -> SchemeDescriptor {
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return SchemeDescriptor(name: name, productName: nil, productKind: .other)
        }
        let referencePattern = #"<BuildableReference\b[^>]*>"#
        let references = matches(pattern: referencePattern, in: source)
        let preferred = references.first { attribute("BlueprintName", in: $0) == name } ?? references.first
        let productName = preferred.flatMap { attribute("BuildableName", in: $0) }
        return SchemeDescriptor(
            name: name,
            productName: productName,
            productKind: productKind(for: productName)
        )
    }

    private static func matches(pattern: String, in source: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            Range(match.range, in: source).map { String(source[$0]) }
        }
    }

    private static func attribute(_ name: String, in source: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let value = matches(pattern: escapedName + #"\s*=\s*"([^"]*)""#, in: source).first,
              let firstQuote = value.firstIndex(of: "\"") else { return nil }
        let remainder = value[value.index(after: firstQuote)...]
        guard let lastQuote = remainder.lastIndex(of: "\"") else { return nil }
        return String(remainder[..<lastQuote])
    }

    private static func productKind(for productName: String?) -> SchemeProductKind {
        guard let productName else { return .other }
        switch URL(fileURLWithPath: productName).pathExtension.lowercased() {
        case "app": return .app
        case "appex": return .appExtension
        case "xctest": return .test
        case "framework", "xcframework": return .framework
        case "a", "dylib": return .library
        case "": return .commandLineTool
        default: return .other
        }
    }

}

import Foundation

enum XcodeOutputParser {
    static func localSchemes(in project: XcodeProject) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: project.url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var names: Set<String> = []
        for case let fileURL as URL in enumerator
        where fileURL.pathExtension == "xcscheme" && fileURL.path.contains("/xcschemes/") {
            names.insert(fileURL.deletingPathExtension().lastPathComponent)
        }
        return names.sorted()
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
            let identifier = fields["id"].flatMap { $0 == "dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder" ? nil : $0 }
            let error = fields["error"]
            let generic = identifier == nil || name.hasPrefix("Any ") || error != nil
            return RunDestination(
                platform: platform,
                name: name,
                identifier: identifier,
                isGeneric: generic
            )
        }
    }

    static func appBuildSettings(from data: Data) throws -> (path: URL, bundleIdentifier: String, executableName: String) {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let targets = object as? [[String: Any]] else { throw RunError.appProductNotFound }

        for target in targets {
            guard
                let settings = target["buildSettings"] as? [String: Any],
                settings["WRAPPER_EXTENSION"] as? String == "app",
                let directory = settings["TARGET_BUILD_DIR"] as? String,
                let product = settings["FULL_PRODUCT_NAME"] as? String,
                let bundleIdentifier = settings["PRODUCT_BUNDLE_IDENTIFIER"] as? String,
                let executableName = settings["EXECUTABLE_NAME"] as? String
            else { continue }

            return (URL(fileURLWithPath: directory).appendingPathComponent(product), bundleIdentifier, executableName)
        }

        throw RunError.appProductNotFound
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
}

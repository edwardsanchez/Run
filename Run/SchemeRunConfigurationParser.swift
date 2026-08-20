import Foundation

enum SchemeRunConfigurationParser {
    static func configuration(in project: XcodeProject, scheme: String) throws -> SchemeRunConfiguration {
        guard let fileURL = schemeFileURL(in: project, scheme: scheme) else {
            return .fallback
        }

        let parser = XMLParser(contentsOf: fileURL)
        let delegate = Delegate()
        parser?.delegate = delegate
        guard parser?.parse() == true, let configuration = delegate.configuration else {
            throw RunError.invalidScheme(scheme)
        }
        return configuration
    }

    static func schemeFileURL(in project: XcodeProject, scheme: String) -> URL? {
        let fileName = scheme + ".xcscheme"
        for container in schemeContainers(for: project) {
            let shared = container.appendingPathComponent("xcshareddata/xcschemes").appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: shared.path) { return shared }

            let userData = container.appendingPathComponent("xcuserdata")
            guard let users = try? FileManager.default.contentsOfDirectory(
                at: userData,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for user in users.sorted(by: { $0.path < $1.path }) {
                let candidate = user.appendingPathComponent("xcschemes").appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    private static func schemeContainers(for project: XcodeProject) -> [URL] {
        guard project.kind == .workspace else { return [project.url] }

        let contentsURL = project.url.appendingPathComponent("contents.xcworkspacedata")
        guard let source = try? String(contentsOf: contentsURL, encoding: .utf8) else {
            return [project.url]
        }

        let pattern = #"location\s*=\s*\"(?:group|container|absolute):([^\"]+\.xcodeproj)\""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [project.url] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let projectURLs = expression.matches(in: source, range: range).compactMap { match -> URL? in
            guard let matchRange = Range(match.range(at: 1), in: source) else { return nil }
            let path = String(source[matchRange])
            if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
            return project.url.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
        }
        return [project.url] + projectURLs
    }
}

private extension SchemeRunConfigurationParser {
    final class Delegate: NSObject, XMLParserDelegate {
        private enum ActionCollection {
            case pre
            case post
        }

        private var isInLaunchAction = false
        private var isInRunnable = false
        private var isInActionContent = false
        private var actionCollection: ActionCollection?
        private var currentAction: (title: String, script: String, targetName: String?)?

        private var buildConfiguration = "Debug"
        private var runnableKind: SchemeRunnableKind?
        private var launchStyle = "0"
        private var executableTargetName: String?
        private var executableProductName: String?
        private var argumentEntries: [String] = []
        private var environment: [String: String] = [:]
        private var workingDirectory: String?
        private var preActions: [SchemeExecutionAction] = []
        private var postActions: [SchemeExecutionAction] = []
        private var enablesAddressSanitizer = false
        private var enablesThreadSanitizer = false
        private var enablesUndefinedBehaviorSanitizer = false

        private(set) var configuration: SchemeRunConfiguration?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "LaunchAction":
                isInLaunchAction = true
                buildConfiguration = attributeDict["buildConfiguration"] ?? "Debug"
                launchStyle = attributeDict["launchStyle"] ?? "0"
                if isYes(attributeDict["useCustomWorkingDirectory"]) {
                    workingDirectory = attributeDict["customWorkingDirectory"]
                }
                enablesAddressSanitizer = isYes(attributeDict["enableAddressSanitizer"])
                enablesThreadSanitizer = isYes(attributeDict["enableThreadSanitizer"])
                enablesUndefinedBehaviorSanitizer = isYes(attributeDict["enableUBSanitizer"])
                    || isYes(attributeDict["enableUndefinedBehaviorSanitizer"])
            case "PreActions" where isInLaunchAction:
                actionCollection = .pre
            case "PostActions" where isInLaunchAction:
                actionCollection = .post
            case "ExecutionAction" where isInLaunchAction && actionCollection != nil:
                currentAction = ("Run Script", "", nil)
            case "ActionContent" where currentAction != nil:
                isInActionContent = true
                currentAction?.title = attributeDict["title"] ?? "Run Script"
                currentAction?.script = attributeDict["scriptText"] ?? ""
            case "BuildableProductRunnable" where isInLaunchAction:
                isInRunnable = true
                runnableKind = .buildableProduct
            case "PathRunnable" where isInLaunchAction,
                 "RemoteRunnable" where isInLaunchAction:
                runnableKind = .unsupported(elementName)
            case "BuildableReference" where isInRunnable:
                executableTargetName = attributeDict["BlueprintName"]
                executableProductName = attributeDict["BuildableName"]
            case "BuildableReference" where isInActionContent && currentAction != nil:
                currentAction?.targetName = attributeDict["BlueprintName"]
            case "CommandLineArgument" where isInLaunchAction && isYes(attributeDict["isEnabled"]):
                if let argument = attributeDict["argument"] { argumentEntries.append(argument) }
            case "EnvironmentVariable" where isInLaunchAction && isYes(attributeDict["isEnabled"]):
                if let key = attributeDict["key"], let value = attributeDict["value"] {
                    environment[key] = value
                }
            default:
                break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch elementName {
            case "BuildableProductRunnable":
                isInRunnable = false
            case "ActionContent":
                isInActionContent = false
            case "ExecutionAction":
                if let currentAction, !currentAction.script.isEmpty {
                    let action = SchemeExecutionAction(
                        title: currentAction.title,
                        script: currentAction.script,
                        targetName: currentAction.targetName
                    )
                    switch actionCollection {
                    case .pre: preActions.append(action)
                    case .post: postActions.append(action)
                    case nil: break
                    }
                }
                currentAction = nil
            case "PreActions", "PostActions":
                actionCollection = nil
            case "LaunchAction":
                isInLaunchAction = false
                configuration = SchemeRunConfiguration(
                    runnableKind: runnableKind ?? .unsupported("missing runnable"),
                    launchStyle: launchStyle,
                    buildConfiguration: buildConfiguration,
                    executableTargetName: executableTargetName,
                    executableProductName: executableProductName,
                    argumentEntries: argumentEntries,
                    environment: environment,
                    workingDirectory: workingDirectory,
                    preActions: preActions,
                    postActions: postActions,
                    enablesAddressSanitizer: enablesAddressSanitizer,
                    enablesThreadSanitizer: enablesThreadSanitizer,
                    enablesUndefinedBehaviorSanitizer: enablesUndefinedBehaviorSanitizer
                )
            default:
                break
            }
        }

        private func isYes(_ value: String?) -> Bool {
            value == "YES" || value?.lowercased() == "true"
        }
    }
}

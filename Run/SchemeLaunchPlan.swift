import Foundation

enum SchemeLaunchPlan {
    static func resolve(
        _ configuration: SchemeRunConfiguration,
        buildSettings: [String: String],
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ResolvedSchemeRunConfiguration {
        let expansionValues = inheritedEnvironment.merging(buildSettings) { _, buildSetting in buildSetting }
        let arguments = configuration.argumentEntries.flatMap {
            shellWords(in: expandMacros(in: $0, values: expansionValues))
        }
        let environment = configuration.environment.mapValues {
            expandMacros(in: $0, values: expansionValues)
        }
        let workingDirectory = configuration.workingDirectory.map {
            let path = expandMacros(in: $0, values: expansionValues)
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }

        return ResolvedSchemeRunConfiguration(
            buildConfiguration: configuration.buildConfiguration,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            preActions: configuration.preActions,
            postActions: configuration.postActions,
            enablesAddressSanitizer: configuration.enablesAddressSanitizer,
            enablesThreadSanitizer: configuration.enablesThreadSanitizer,
            enablesUndefinedBehaviorSanitizer: configuration.enablesUndefinedBehaviorSanitizer
        )
    }

    static func sanitizerArguments(for configuration: SchemeRunConfiguration) -> [String] {
        var arguments: [String] = []
        if configuration.enablesAddressSanitizer {
            arguments += ["-enableAddressSanitizer", "YES"]
        }
        if configuration.enablesThreadSanitizer {
            arguments += ["-enableThreadSanitizer", "YES"]
        }
        if configuration.enablesUndefinedBehaviorSanitizer {
            arguments += ["-enableUndefinedBehaviorSanitizer", "YES"]
        }
        return arguments
    }

    static func simulatorLaunchArguments(
        identifier: String,
        bundleIdentifier: String,
        configuration: ResolvedSchemeRunConfiguration
    ) -> [String] {
        ["launch", "--terminate-running-process", identifier, bundleIdentifier] + configuration.arguments
    }

    static func simulatorEnvironment(for configuration: ResolvedSchemeRunConfiguration) -> [String: String] {
        Dictionary(uniqueKeysWithValues: configuration.environment.map { ("SIMCTL_CHILD_" + $0.key, $0.value) })
    }

    static func deviceLaunchArguments(
        identifier: String,
        bundleIdentifier: String,
        configuration: ResolvedSchemeRunConfiguration
    ) -> [String] {
        var arguments = [
            "device", "process", "launch", "--device", identifier,
            "--terminate-existing", "--json-output", "-",
        ]
        if let workingDirectory = configuration.workingDirectory {
            arguments += ["--working-directory", workingDirectory.path]
        }
        return arguments + [bundleIdentifier] + configuration.arguments
    }

    static func deviceEnvironment(for configuration: ResolvedSchemeRunConfiguration) -> [String: String] {
        Dictionary(uniqueKeysWithValues: configuration.environment.map { ("DEVICECTL_CHILD_" + $0.key, $0.value) })
    }

    private static func expandMacros(in source: String, values: [String: String]) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"\$\(([^)]+)\)"#) else { return source }
        var result = source
        for _ in 0..<64 {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            guard let match = expression.firstMatch(in: result, range: range),
                  let wholeRange = Range(match.range(at: 0), in: result),
                  let nameRange = Range(match.range(at: 1), in: result),
                  let value = values[String(result[nameRange])]
            else { return result }
            guard String(result[wholeRange]) != value else { return result }
            result.replaceSubrange(wholeRange, with: value)
        }
        return result
    }

    private static func shellWords(in source: String) -> [String] {
        enum Quote { case single, double }

        var words: [String] = []
        var word = ""
        var quote: Quote?
        var isEscaping = false
        var hasContent = false

        func finishWord() {
            if hasContent {
                words.append(word)
                word = ""
                hasContent = false
            }
        }

        for character in source {
            if isEscaping {
                word.append(character)
                hasContent = true
                isEscaping = false
                continue
            }

            switch (quote, character) {
            case (.single, "'"):
                quote = nil
                hasContent = true
            case (.double, "\""):
                quote = nil
                hasContent = true
            case (nil, "'"):
                quote = .single
                hasContent = true
            case (nil, "\""):
                quote = .double
                hasContent = true
            case (.single, _):
                word.append(character)
                hasContent = true
            case (_, "\\"):
                isEscaping = true
                hasContent = true
            case (nil, let character) where character.isWhitespace:
                finishWord()
            default:
                word.append(character)
                hasContent = true
            }
        }
        if isEscaping { word.append("\\") }
        finishWord()
        return words
    }
}

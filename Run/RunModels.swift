import Foundation

enum XcodeContainerKind: String, Codable, Sendable {
    case project
    case workspace

    var commandFlag: String {
        switch self {
        case .project: "-project"
        case .workspace: "-workspace"
        }
    }
}

struct XcodeProject: Codable, Equatable, Identifiable, Sendable {
    let url: URL
    let kind: XcodeContainerKind

    var id: String { url.standardizedFileURL.path }
    var name: String { url.deletingPathExtension().lastPathComponent }

    nonisolated init?(url: URL) {
        let resolvedURL = url.standardizedFileURL
        switch resolvedURL.pathExtension.lowercased() {
        case "xcodeproj": kind = .project
        case "xcworkspace": kind = .workspace
        default: return nil
        }
        self.url = resolvedURL
    }
}

enum ExternalProjectOpenRequest {
    static func project(in urls: [URL]) -> XcodeProject? {
        urls.lazy.compactMap(XcodeProject.init(url:)).first
    }
}

enum CurrentProjectOpenAction {
    static func perform(for project: XcodeProject?, open: (URL) -> Void) {
        guard let project else { return }
        open(project.url)
    }
}

struct RunDestination: Codable, Equatable, Hashable, Identifiable, Sendable {
    let platform: String
    let name: String
    let identifier: String?
    let isGeneric: Bool
    let osVersion: String?
    let availabilityError: String?
    let connectionKind: DestinationConnectionKind?

    init(
        platform: String,
        name: String,
        identifier: String?,
        isGeneric: Bool,
        osVersion: String? = nil,
        availabilityError: String? = nil,
        connectionKind: DestinationConnectionKind? = nil
    ) {
        self.platform = platform
        self.name = name
        self.identifier = identifier
        self.isGeneric = isGeneric
        self.osVersion = osVersion
        self.availabilityError = availabilityError
        self.connectionKind = connectionKind
    }

    var id: String {
        [identifier ?? "generic", platform, name, availabilityError ?? "available"]
            .joined(separator: "|")
    }
    var isSimulator: Bool { platform.localizedCaseInsensitiveContains("simulator") }
    var isMac: Bool { platform == "macOS" }
    var isRunnable: Bool { !isGeneric && identifier != nil && availabilityError == nil }
    var commandSpecifier: String { identifier.map { "id=\($0)" } ?? "platform=\(platform),name=\(name)" }

    var symbolName: String {
        let combined = "\(platform) \(name)".lowercased()
        if isMac { return "macbook" }
        if combined.contains("vision") { return "visionpro" }
        if combined.contains("watch") { return "applewatch" }
        if combined.contains("tv") { return "appletv" }
        if combined.contains("ipad") { return "ipad" }
        if combined.contains("iphone") || platform == "iOS" || isSimulator { return "iphone" }
        return "desktopcomputer"
    }

    func addingMetadata(osVersion: String?, connectionKind: DestinationConnectionKind?) -> RunDestination {
        RunDestination(
            platform: platform,
            name: name,
            identifier: identifier,
            isGeneric: isGeneric,
            osVersion: self.osVersion ?? osVersion,
            availabilityError: availabilityError,
            connectionKind: connectionKind
        )
    }
}

enum DestinationConnectionKind: String, Codable, Sendable {
    case local
    case wireless
    case cloud

    var symbolName: String? {
        switch self {
        case .local: nil
        case .wireless: "network"
        case .cloud: "cloud"
        }
    }
}

enum SchemeProductKind: String, Codable, Sendable {
    case app
    case appExtension
    case test
    case framework
    case library
    case commandLineTool
    case other

    var symbolName: String {
        switch self {
        case .app: "app"
        case .appExtension: "puzzlepiece.extension"
        case .test: "checkmark.diamond"
        case .framework: "shippingbox"
        case .library: "books.vertical"
        case .commandLineTool: "terminal"
        case .other: "gearshape"
        }
    }
}

struct SchemeDescriptor: Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let productName: String?
    let productKind: SchemeProductKind
    let appIconName: String?

    init(
        name: String,
        productName: String?,
        productKind: SchemeProductKind,
        appIconName: String? = nil
    ) {
        self.name = name
        self.productName = productName
        self.productKind = productKind
        self.appIconName = appIconName
    }

    var id: String { name }
    var symbolName: String { productKind.symbolName }
    var usesAppIconFallback: Bool { productKind == .app }
}

struct RunDestinationGroup: Equatable, Identifiable, Sendable {
    let name: String
    let destinations: [RunDestination]

    var id: String { name }
}

enum RunPhase: Equatable, Sendable {
    case idle
    case loading
    case building
    case running
    case stopping
    case failed(String)

    var isActive: Bool {
        switch self {
        case .building, .running, .stopping: true
        default: false
        }
    }
}

enum SingleInstancePolicy {
    static func processIdentifiersToTerminate(
        currentProcessIdentifier: Int32,
        runningProcessIdentifiers: [Int32]
    ) -> [Int32] {
        runningProcessIdentifiers.filter { $0 != currentProcessIdentifier }
    }
}

struct LaunchContext: Equatable, Sendable {
    let bundleIdentifier: String
    let executableName: String
    let destination: RunDestination
    let deviceProcessIdentifier: Int?
    let postActions: [PreparedSchemeExecutionAction]
}

struct SchemeExecutionAction: Equatable, Sendable {
    let title: String
    let script: String
    let targetName: String?
}

struct PreparedSchemeExecutionAction: Equatable, Sendable {
    let action: SchemeExecutionAction
    let environment: [String: String]
    let workingDirectory: URL?
}

struct SchemeRunConfiguration: Equatable, Sendable {
    let runnableKind: SchemeRunnableKind
    let launchStyle: String
    let buildConfiguration: String
    let executableTargetName: String?
    let executableProductName: String?
    let argumentEntries: [String]
    let environment: [String: String]
    let workingDirectory: String?
    let preActions: [SchemeExecutionAction]
    let postActions: [SchemeExecutionAction]
    let enablesAddressSanitizer: Bool
    let enablesThreadSanitizer: Bool
    let enablesUndefinedBehaviorSanitizer: Bool

    static let fallback = SchemeRunConfiguration(
        runnableKind: .generated,
        launchStyle: "0",
        buildConfiguration: "Debug",
        executableTargetName: nil,
        executableProductName: nil,
        argumentEntries: [],
        environment: [:],
        workingDirectory: nil,
        preActions: [],
        postActions: [],
        enablesAddressSanitizer: false,
        enablesThreadSanitizer: false,
        enablesUndefinedBehaviorSanitizer: false
    )
}

enum SchemeRunnableKind: Equatable, Sendable {
    case generated
    case buildableProduct
    case unsupported(String)
}

struct AppBuildSettings: Equatable, Sendable {
    let path: URL
    let bundleIdentifier: String
    let executableName: String
    let targetName: String?
    let values: [String: String]
}

struct TargetBuildSettings: Equatable, Sendable {
    let targetName: String?
    let values: [String: String]
}

struct ResolvedSchemeRunConfiguration: Equatable, Sendable {
    let buildConfiguration: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL?
    let preActions: [SchemeExecutionAction]
    let postActions: [SchemeExecutionAction]
    let enablesAddressSanitizer: Bool
    let enablesThreadSanitizer: Bool
    let enablesUndefinedBehaviorSanitizer: Bool
}

struct ProjectConfiguration: Equatable, Sendable {
    let schemes: [String]
    let destinations: [RunDestination]
    let selectedScheme: String?
    let selectedDestination: RunDestination?
}

enum RunError: LocalizedError, Equatable {
    case invalidProject
    case noSchemes
    case noDestinations
    case noRunnableDestination
    case commandFailed(String)
    case appProductNotFound
    case invalidScheme(String)
    case unsupportedRunAction(String)

    var errorDescription: String? {
        switch self {
        case .invalidProject: "Choose an .xcodeproj or .xcworkspace file."
        case .noSchemes: "This project does not contain a runnable scheme."
        case .noDestinations: "No compatible run destinations were found for this scheme."
        case .noRunnableDestination: "Choose a concrete device, Simulator, or Mac destination."
        case .commandFailed(let message): message
        case .appProductNotFound: "The selected scheme did not produce an app that Run can launch."
        case .invalidScheme(let name): "The \(name) scheme's Run action could not be read."
        case .unsupportedRunAction(let detail): "This scheme's Run action is not supported yet: \(detail)."
        }
    }
}

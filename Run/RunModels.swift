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

    init?(url: URL) {
        let resolvedURL = url.standardizedFileURL
        switch resolvedURL.pathExtension.lowercased() {
        case "xcodeproj": kind = .project
        case "xcworkspace": kind = .workspace
        default: return nil
        }
        self.url = resolvedURL
    }
}

struct RunDestination: Codable, Equatable, Hashable, Identifiable, Sendable {
    let platform: String
    let name: String
    let identifier: String?
    let isGeneric: Bool

    var id: String { identifier ?? "\(platform)|\(name)" }
    var isSimulator: Bool { platform.localizedCaseInsensitiveContains("simulator") }
    var isMac: Bool { platform == "macOS" }
    var isRunnable: Bool { !isGeneric && identifier != nil }
    var commandSpecifier: String { identifier.map { "id=\($0)" } ?? "platform=\(platform),name=\(name)" }
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

struct LaunchContext: Equatable, Sendable {
    let bundleIdentifier: String
    let executableName: String
    let destination: RunDestination
    let deviceProcessIdentifier: Int?
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

    var errorDescription: String? {
        switch self {
        case .invalidProject: "Choose an .xcodeproj or .xcworkspace file."
        case .noSchemes: "This project does not contain a runnable scheme."
        case .noDestinations: "No compatible run destinations were found for this scheme."
        case .noRunnableDestination: "Choose a concrete device, Simulator, or Mac destination."
        case .commandFailed(let message): message
        case .appProductNotFound: "The selected scheme did not produce an app that Run can launch."
        }
    }
}

import Foundation

enum RecentProjectsPolicy {
    static let maximumCount = 5

    static func limited(_ projects: [XcodeProject]) -> [XcodeProject] {
        Array(projects.prefix(maximumCount))
    }
}

protocol RecentProjectsPersisting: AnyObject {
    func load() -> [XcodeProject]
    func save(_ projects: [XcodeProject])
}

final class UserDefaultsRecentProjectsStore: RecentProjectsPersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "recentProjects") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [XcodeProject] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([XcodeProject].self, from: data)) ?? []
    }

    func save(_ projects: [XcodeProject]) {
        defaults.set(try? JSONEncoder().encode(projects), forKey: key)
    }
}

final class SelectionStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func scheme(for project: XcodeProject) -> String? {
        defaults.string(forKey: "scheme.\(project.id)")
    }

    func destinationID(for project: XcodeProject) -> String? {
        defaults.string(forKey: "destination.\(project.id)")
    }

    func save(scheme: String?, destinationID: String?, for project: XcodeProject) {
        defaults.set(scheme, forKey: "scheme.\(project.id)")
        defaults.set(destinationID, forKey: "destination.\(project.id)")
    }

    func recentDestinationIDs(for project: XcodeProject, scheme: String) -> [String] {
        defaults.stringArray(forKey: recentDestinationsKey(for: project, scheme: scheme)) ?? []
    }

    func rememberDestination(
        _ destinationID: String,
        for project: XcodeProject,
        scheme: String,
        limit: Int = 5
    ) -> [String] {
        var identifiers = recentDestinationIDs(for: project, scheme: scheme)
        identifiers.removeAll { $0 == destinationID }
        identifiers.insert(destinationID, at: 0)
        identifiers = Array(identifiers.prefix(limit))
        defaults.set(identifiers, forKey: recentDestinationsKey(for: project, scheme: scheme))
        return identifiers
    }

    private func recentDestinationsKey(for project: XcodeProject, scheme: String) -> String {
        "recentDestinations.\(project.id).\(scheme)"
    }
}

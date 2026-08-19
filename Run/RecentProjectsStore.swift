import Foundation

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
}

import Foundation

enum RecentProjectsPolicy {
    static let maximumCount = 10

    static func limited(_ projects: [XcodeProject]) -> [XcodeProject] {
        Array(projects.prefix(maximumCount))
    }

    static func grouped(_ projects: [XcodeProject]) -> [RecentProjectGroup] {
        var projectsByName: [String: [XcodeProject]] = [:]
        var orderedNames: [String] = []

        for project in projects {
            if projectsByName[project.name] == nil {
                orderedNames.append(project.name)
            }
            projectsByName[project.name, default: []].append(project)
        }

        return orderedNames.compactMap { name in
            projectsByName[name].map {
                RecentProjectGroup(name: name, projects: $0)
            }
        }
    }

    static func removing(projectID: XcodeProject.ID, from projects: [XcodeProject]) -> [XcodeProject] {
        projects.filter { $0.id != projectID }
    }

    static func iconProject(
        in group: RecentProjectGroup,
        availableIconProjectIDs: Set<XcodeProject.ID>
    ) -> XcodeProject? {
        group.projects.first { availableIconProjectIDs.contains($0.id) }
            ?? group.projects.first
    }

    static func disambiguatingLabel(
        for project: XcodeProject,
        among projects: [XcodeProject],
        worktreeName: String? = nil
    ) -> String? {
        let matchingProjects = projects.filter { $0.name == project.name }
        guard matchingProjects.count > 1 else { return nil }
        if let worktreeName { return worktreeName }

        let directoryURL = project.url.deletingLastPathComponent().standardizedFileURL
        let directoryComponents = directoryURL.pathComponents
        let matchingDirectoryComponents = matchingProjects.map {
            $0.url.deletingLastPathComponent().standardizedFileURL.pathComponents
        }
        let sharedComponentCount = matchingDirectoryComponents.reduce(
            directoryComponents.count
        ) { currentCount, components in
            min(
                currentCount,
                zip(directoryComponents, components).prefix { $0 == $1 }.count
            )
        }

        guard sharedComponentCount > 1,
              sharedComponentCount < directoryComponents.count else {
            return directoryURL.path
        }
        return "…/" + directoryComponents.dropFirst(sharedComponentCount).joined(separator: "/")
    }
}

struct RecentProjectGroup: Equatable, Identifiable, Sendable {
    let name: String
    let projects: [XcodeProject]

    var id: String { name }
    var isDuplicate: Bool { projects.count > 1 }
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

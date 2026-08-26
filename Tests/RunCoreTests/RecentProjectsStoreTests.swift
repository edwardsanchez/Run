import Foundation
import Testing
@testable import RunCore

struct RecentProjectsStoreTests {
    @Test func firstLaunchHasDisabledNoRecentsState() {
        let menu = MenuContent(recentProjectNames: [])
        #expect(!menu.hasRecents)
        #expect(menu.recentsPlaceholder == "No Recents")
        #expect(menu.topLevelTitles == ["Open…", "No Recents", "—", "Quit"])
    }

    @Test func populatedMenuEnablesRecentsAndRemovesPlaceholder() {
        let menu = MenuContent(recentProjectNames: ["Demo"])
        #expect(menu.hasRecents)
        #expect(menu.recentsPlaceholder == nil)
    }

    @Test func openedProjectMenuContainsAllControlsBeforeOpenAndRecents() {
        let menu = MenuContent(
            projectName: "Demo",
            selectedSchemeName: "Demo App",
            selectedDestinationName: "My Mac",
            recentProjectNames: ["Demo"]
        )
        #expect(menu.topLevelTitles == [
            "Demo", "Scheme: Demo App", "Run Destination: My Mac", "—",
            "Open…", "Recents", "—", "Quit",
        ])
    }

    @Test func recentProjectsRoundTripAndCanBeCleared() throws {
        let suite = "RunTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsRecentProjectsStore(defaults: defaults, key: "testRecents")
        let project = try #require(XcodeProject(url: URL(fileURLWithPath: "/tmp/Demo.xcodeproj")))

        store.save([project])
        #expect(store.load() == [project])
        store.save([])
        #expect(store.load().isEmpty)
    }

    @Test func recentProjectsAreLimitedToFiveInMostRecentOrder() throws {
        let projects = try (0..<7).map { index in
            try #require(XcodeProject(url: URL(fileURLWithPath: "/tmp/Project\(index).xcodeproj")))
        }

        let limited = RecentProjectsPolicy.limited(projects)

        #expect(RecentProjectsPolicy.maximumCount == 5)
        #expect(limited == Array(projects.prefix(5)))
    }

    @Test func duplicateProjectNamesAreDisambiguatedByTheirContainingPaths() throws {
        let mainProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Users/example/Sources/Demo/Demo.xcodeproj")
        ))
        let worktreeProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Users/example/Worktrees/feature/Demo.xcodeproj")
        ))
        let otherProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Users/example/Sources/Other.xcodeproj")
        ))
        let projects = [mainProject, worktreeProject, otherProject]

        #expect(RecentProjectsPolicy.disambiguatingPath(
            for: mainProject,
            among: projects
        ) == "/Users/example/Sources/Demo")
        #expect(RecentProjectsPolicy.disambiguatingPath(
            for: worktreeProject,
            among: projects
        ) == "/Users/example/Worktrees/feature")
        #expect(RecentProjectsPolicy.disambiguatingPath(
            for: otherProject,
            among: projects
        ) == nil)
    }

    @Test func selectedSchemeAndDestinationRoundTrip() throws {
        let suite = "RunSelections.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        let project = try #require(XcodeProject(url: URL(fileURLWithPath: "/tmp/Demo.xcworkspace")))

        store.save(scheme: "Demo", destinationID: "SIM-ID", for: project)
        #expect(store.scheme(for: project) == "Demo")
        #expect(store.destinationID(for: project) == "SIM-ID")
    }

    @Test func remembersRecentDestinationsPerSchemeInMostRecentOrder() throws {
        let suite = "RunDestinationRecents.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SelectionStore(defaults: defaults)
        let project = try #require(XcodeProject(url: URL(fileURLWithPath: "/tmp/Demo.xcodeproj")))

        _ = store.rememberDestination("PHONE", for: project, scheme: "Demo")
        _ = store.rememberDestination("SIM", for: project, scheme: "Demo")
        _ = store.rememberDestination("PHONE", for: project, scheme: "Demo")

        #expect(store.recentDestinationIDs(for: project, scheme: "Demo") == ["PHONE", "SIM"])
        #expect(store.recentDestinationIDs(for: project, scheme: "Other").isEmpty)
    }
}

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

    @Test func recentProjectsAreLimitedToTenInMostRecentOrder() throws {
        let projects = try (0..<12).map { index in
            try #require(XcodeProject(url: URL(fileURLWithPath: "/tmp/Project\(index).xcodeproj")))
        }

        let limited = RecentProjectsPolicy.limited(projects)

        #expect(RecentProjectsPolicy.maximumCount == 10)
        #expect(limited == Array(projects.prefix(10)))
    }

    @Test func duplicateProjectsAreGroupedWithoutHidingAnyRecentPath() throws {
        let newestDemo = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/tmp/worktrees/newest/Demo.xcodeproj")
        ))
        let other = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/tmp/Other.xcodeproj")
        ))
        let olderDemo = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/tmp/worktrees/older/Demo.xcodeproj")
        ))

        let groups = RecentProjectsPolicy.grouped([newestDemo, other, olderDemo])

        #expect(groups.map(\.name) == ["Demo", "Other"])
        #expect(groups[0].isDuplicate)
        #expect(groups[0].projects == [newestDemo, olderDemo])
        #expect(!groups[1].isDuplicate)
        #expect(groups[1].projects == [other])
        #expect(groups.flatMap(\.projects).count == 3)
    }

    @Test func removingOneRecentProjectPreservesTheOthersInOrder() throws {
        let projects = try (0..<3).map { index in
            try #require(XcodeProject(url: URL(fileURLWithPath: "/tmp/Project\(index).xcodeproj")))
        }

        let remaining = RecentProjectsPolicy.removing(
            projectID: projects[1].id,
            from: projects
        )

        #expect(remaining == [projects[0], projects[2]])
    }

    @Test func duplicateGroupUsesTheFirstProjectWithAResolvedIcon() throws {
        let first = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/tmp/worktrees/first/Demo.xcodeproj")
        ))
        let second = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/tmp/worktrees/second/Demo.xcodeproj")
        ))
        let third = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/tmp/worktrees/third/Demo.xcodeproj")
        ))
        let group = RecentProjectGroup(name: "Demo", projects: [first, second, third])

        #expect(RecentProjectsPolicy.iconProject(
            in: group,
            availableIconProjectIDs: [second.id, third.id]
        ) == second)
        #expect(RecentProjectsPolicy.iconProject(
            in: group,
            availableIconProjectIDs: []
        ) == first)
    }

    @Test func duplicateProjectNamesAreDisambiguatedByTheirContainingPaths() throws {
        let mainProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Users/example/Sources/Demo/Demo.xcodeproj")
        ))
        let worktreeProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Users/example/Worktrees/feature/Demo.xcodeproj")
        ))
        let otherProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Volumes/Builds/Other.xcodeproj")
        ))
        let projects = [mainProject, worktreeProject, otherProject]

        #expect(RecentProjectsPolicy.disambiguatingLabel(
            for: mainProject,
            among: projects
        ) == "…/Sources/Demo")
        #expect(RecentProjectsPolicy.disambiguatingLabel(
            for: worktreeProject,
            among: projects
        ) == "…/Worktrees/feature")
        #expect(RecentProjectsPolicy.disambiguatingLabel(
            for: otherProject,
            among: projects
        ) == nil)
    }

    @Test func duplicateProjectPathsRemainAbsoluteWithoutAMeaningfulSharedPrefix() throws {
        let localProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Users/example/Sources/Demo.xcodeproj")
        ))
        let externalProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Volumes/Worktrees/Demo.xcodeproj")
        ))

        #expect(RecentProjectsPolicy.disambiguatingLabel(
            for: localProject,
            among: [localProject, externalProject]
        ) == "/Users/example/Sources")
        #expect(RecentProjectsPolicy.disambiguatingLabel(
            for: externalProject,
            among: [localProject, externalProject]
        ) == "/Volumes/Worktrees")
    }

    @Test func attachedWorktreeNameTakesPriorityOnlyForDuplicateProjects() throws {
        let mainProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Users/example/Sources/Demo.xcodeproj")
        ))
        let worktreeProject = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/Users/example/Worktrees/Demo.xcodeproj")
        ))

        #expect(RecentProjectsPolicy.disambiguatingLabel(
            for: worktreeProject,
            among: [mainProject, worktreeProject],
            worktreeName: "codex/settings-icons"
        ) == "codex/settings-icons")
        #expect(RecentProjectsPolicy.disambiguatingLabel(
            for: worktreeProject,
            among: [worktreeProject],
            worktreeName: "codex/settings-icons"
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

import Foundation
import Testing
@testable import RunCore

struct ExternalProjectOpenRequestTests {
    @Test func acceptsXcodeProjectsFromFinder() throws {
        let url = URL(fileURLWithPath: "/tmp/Demo.xcodeproj")

        let project = try #require(ExternalProjectOpenRequest.project(in: [url]))

        #expect(project.kind == .project)
        #expect(project.url == url)
    }

    @Test func acceptsXcodeWorkspacesFromFinder() throws {
        let url = URL(fileURLWithPath: "/tmp/Demo.xcworkspace")

        let project = try #require(ExternalProjectOpenRequest.project(in: [url]))

        #expect(project.kind == .workspace)
        #expect(project.url == url)
    }

    @Test func ignoresUnsupportedFilesAndUsesTheFirstSupportedContainer() throws {
        let projectURL = URL(fileURLWithPath: "/tmp/First.xcodeproj")
        let workspaceURL = URL(fileURLWithPath: "/tmp/Second.xcworkspace")

        let project = try #require(ExternalProjectOpenRequest.project(in: [
            URL(fileURLWithPath: "/tmp/Notes.txt"),
            projectURL,
            workspaceURL,
        ]))

        #expect(project.url == projectURL)
        #expect(ExternalProjectOpenRequest.project(in: [
            URL(fileURLWithPath: "/tmp/Notes.txt"),
        ]) == nil)
    }
}

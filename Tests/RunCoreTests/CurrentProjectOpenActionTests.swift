import Foundation
import Testing
@testable import RunCore

struct CurrentProjectOpenActionTests {
    @Test func opensTheCurrentProjectURL() throws {
        let project = try #require(XcodeProject(
            url: URL(fileURLWithPath: "/tmp/Monogram.xcodeproj")
        ))
        var openedURLs: [URL] = []

        CurrentProjectOpenAction.perform(for: project) { openedURLs.append($0) }

        #expect(openedURLs == [project.url])
    }

    @Test func doesNothingWithoutACurrentProject() {
        var openedURLs: [URL] = []

        CurrentProjectOpenAction.perform(for: nil) { openedURLs.append($0) }

        #expect(openedURLs.isEmpty)
    }
}

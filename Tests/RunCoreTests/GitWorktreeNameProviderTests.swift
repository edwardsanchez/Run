import Foundation
import Testing
@testable import RunCore

struct GitWorktreeNameProviderTests {
    @Test func returnsBranchOrDetachedRevisionOnlyForLinkedWorktrees() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RunGitWorktreeTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appending(path: "main")
        let attached = root.appending(path: "attached")
        let detached = root.appending(path: "detached")

        try runGit(["init", main.path])
        try runGit(["-C", main.path, "config", "user.email", "run-tests@example.com"])
        try runGit(["-C", main.path, "config", "user.name", "Run Tests"])
        try Data("fixture".utf8).write(to: main.appending(path: "README"))
        try runGit(["-C", main.path, "add", "README"])
        try runGit(["-C", main.path, "commit", "-m", "Initial"])
        try runGit(["-C", main.path, "branch", "feature/worktree-label"])
        try runGit(["-C", main.path, "worktree", "add", attached.path, "feature/worktree-label"])
        try runGit(["-C", main.path, "worktree", "add", "--detach", detached.path, "HEAD"])
        let detachedRevision = try runGit(["-C", detached.path, "rev-parse", "--short=7", "HEAD"])

        let mainProject = try project(in: main)
        let attachedProject = try project(in: attached)
        let detachedProject = try project(in: detached)
        let provider = GitWorktreeNameProvider()

        let mainName = await provider.worktreeName(for: mainProject)
        let attachedName = await provider.worktreeName(for: attachedProject)
        let detachedName = await provider.worktreeName(for: detachedProject)

        #expect(mainName == nil)
        #expect(attachedName == "feature/worktree-label")
        #expect(detachedName == detachedRevision + " (detached)")
    }

    private func project(in directory: URL) throws -> XcodeProject {
        let projectURL = directory.appending(path: "Demo.xcodeproj")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        return try #require(XcodeProject(url: projectURL))
    }

    @discardableResult
    private func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitFixtureError.commandFailed(String(decoding: errorData, as: UTF8.self))
        }
        return String(decoding: outputData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum GitFixtureError: Error {
    case commandFailed(String)
}

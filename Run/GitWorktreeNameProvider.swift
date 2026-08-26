import Foundation

protocol WorktreeNameProviding: Sendable {
    func worktreeName(for project: XcodeProject) async -> String?
}

actor GitWorktreeNameProvider: WorktreeNameProviding {
    func worktreeName(for project: XcodeProject) async -> String? {
        let projectDirectory = project.url.deletingLastPathComponent()
        guard let repositoryPaths = gitOutput(
            arguments: [
                "rev-parse",
                "--path-format=absolute",
                "--git-dir",
                "--git-common-dir",
            ],
            currentDirectory: projectDirectory
        ) else { return nil }

        let paths = repositoryPaths.split(separator: "\n").map(String.init)
        guard paths.count == 2 else { return nil }
        let gitDirectory = normalizedFileURL(for: paths[0])
        let commonGitDirectory = normalizedFileURL(for: paths[1])
        guard gitDirectory != commonGitDirectory else { return nil }

        if let branchName = gitOutput(
            arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
            currentDirectory: projectDirectory
        ) {
            return branchName
        }
        guard let revision = gitOutput(
            arguments: ["rev-parse", "--short=7", "HEAD"],
            currentDirectory: projectDirectory
        ) else { return nil }
        return revision + " (detached)"
    }

    private func gitOutput(arguments: [String], currentDirectory: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func normalizedFileURL(for path: String) -> URL {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }
}

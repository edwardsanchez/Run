enum GlobalRunShortcutAction: Equatable, Sendable {
    case restart
    case bonk
}

enum GlobalRunShortcutPolicy {
    static func action(
        hasProject: Bool,
        hasScheme: Bool,
        hasRunnableDestination: Bool
    ) -> GlobalRunShortcutAction {
        hasProject && hasScheme && hasRunnableDestination ? .restart : .bonk
    }
}

enum RestartRunSequence {
    @MainActor
    static func perform<Context: Sendable>(
        previousContext: Context?,
        stop: @MainActor (Context?) async throws -> Void,
        launch: @MainActor () async throws -> Context
    ) async throws -> Context {
        try await stop(previousContext)
        return try await launch()
    }
}

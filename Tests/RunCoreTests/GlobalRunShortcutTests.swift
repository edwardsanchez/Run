import Carbon.HIToolbox
import Testing
@testable import RunCore

struct GlobalRunShortcutTests {
    @Test(arguments: [
        (false, false, false),
        (true, false, false),
        (true, true, false),
        (false, true, true),
    ])
    func incompleteSelectionBonks(
        hasProject: Bool,
        hasScheme: Bool,
        hasRunnableDestination: Bool
    ) {
        #expect(GlobalRunShortcutPolicy.action(
            hasProject: hasProject,
            hasScheme: hasScheme,
            hasRunnableDestination: hasRunnableDestination
        ) == .bonk)
    }

    @Test func completeSelectionRestarts() {
        #expect(GlobalRunShortcutPolicy.action(
            hasProject: true,
            hasScheme: true,
            hasRunnableDestination: true
        ) == .restart)
    }

    @Test @MainActor func registeredControlRHotKeyInvokesItsAction() {
        var invocationCount = 0
        let shortcut = GlobalRunShortcut {
            invocationCount += 1
        }

        #expect(shortcut.handle(EventHotKeyID(signature: 0x52756E52, id: 1)) == noErr)
        #expect(invocationCount == 1)
    }

    @Test @MainActor func unrelatedHotKeyIsIgnored() {
        var invocationCount = 0
        let shortcut = GlobalRunShortcut {
            invocationCount += 1
        }

        #expect(shortcut.handle(EventHotKeyID(signature: 0, id: 2)) == eventNotHandledErr)
        #expect(invocationCount == 0)
    }

    @Test @MainActor func activeRunStopsBeforeTheReplacementLaunches() async throws {
        let events = EventRecorder()

        let result = try await RestartRunSequence.perform(
            previousContext: "existing run",
            stop: { context in events.record("stop \(context ?? "none")") },
            launch: {
                events.record("launch")
                return "replacement run"
            }
        )

        #expect(result == "replacement run")
        #expect(events.values == ["stop existing run", "launch"])
    }

    @Test @MainActor func idleSelectionRunsNormallyAfterANoOpStop() async throws {
        let events = EventRecorder()

        _ = try await RestartRunSequence.perform(
            previousContext: Optional<String>.none,
            stop: { context in events.record("stop \(context ?? "none")") },
            launch: {
                events.record("launch")
                return "new run"
            }
        )

        #expect(events.values == ["stop none", "launch"])
    }

    @Test @MainActor func failedStopDoesNotLaunchAReplacement() async {
        let events = EventRecorder()

        await #expect(throws: StopFailure.self) {
            _ = try await RestartRunSequence.perform(
                previousContext: "existing run",
                stop: { _ in
                    events.record("stop")
                    throw StopFailure()
                },
                launch: {
                    events.record("launch")
                    return "replacement run"
                }
            )
        }

        #expect(events.values == ["stop"])
    }
}

private struct StopFailure: Error {}

@MainActor
private final class EventRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}

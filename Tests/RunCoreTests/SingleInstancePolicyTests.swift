import Testing
@testable import RunCore

struct SingleInstancePolicyTests {
    @Test func theNewApplicationInstanceReplacesOlderInstances() {
        #expect(SingleInstancePolicy.processIdentifiersToTerminate(
            currentProcessIdentifier: 41,
            runningProcessIdentifiers: [41]
        ) == [])
        #expect(SingleInstancePolicy.processIdentifiersToTerminate(
            currentProcessIdentifier: 42,
            runningProcessIdentifiers: [40, 41, 42]
        ) == [40, 41])
    }
}

import AppKit
import SwiftUI

@main
struct RunApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AppStore()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        let runningApplications = Bundle.main.bundleIdentifier.map {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        } ?? []
        let processIdentifiersToTerminate = Set(SingleInstancePolicy.processIdentifiersToTerminate(
            currentProcessIdentifier: processIdentifier,
            runningProcessIdentifiers: runningApplications.map(\.processIdentifier)
        ))
        for application in runningApplications
        where processIdentifiersToTerminate.contains(application.processIdentifier) {
            application.forceTerminate()
        }

        let controller = StatusItemController(store: store)
        statusItemController = controller

        let arguments = ProcessInfo.processInfo.arguments
        if let projectFlag = arguments.firstIndex(of: "--open-project"),
           arguments.indices.contains(projectFlag + 1) {
            store.openProject(at: URL(fileURLWithPath: arguments[projectFlag + 1]))
        }
        if arguments.contains("--show-menu") {
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                controller.showPopover()
            }
        }
        #if DEBUG
        if arguments.contains("--verification-window") {
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                controller.showVerificationWindow()
            }
        }
        #endif
    }
}

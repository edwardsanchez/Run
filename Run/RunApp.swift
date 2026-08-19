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

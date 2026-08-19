import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: AppStore
    private let nameItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let runItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    #if DEBUG
    private var verificationWindow: NSWindow?
    #endif

    init(store: AppStore) {
        self.store = store
        super.init()

        nameItem.button?.title = "Run"
        nameItem.button?.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        nameItem.button?.toolTip = "Run"
        nameItem.button?.target = self
        nameItem.button?.action = #selector(togglePopover)
        nameItem.button?.sendAction(on: [.leftMouseUp])

        runItem.button?.target = self
        runItem.button?.action = #selector(toggleRun)
        runItem.button?.sendAction(on: [.leftMouseUp])

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView(store: store))
        updateRunItem()

        store.onChange = { [weak self] in
            self?.updateRunItem()
        }
    }

    func showPopover() {
        guard let button = nameItem.button, !popover.isShown else { return }
        NSApplication.shared.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    #if DEBUG
    func showVerificationWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Run Menu Verification"
        window.contentViewController = NSHostingController(rootView: MenuBarPopoverView(store: store))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        verificationWindow = window
    }
    #endif

    private func updateRunItem() {
        let isActive = store.phase.isActive
        runItem.button?.image = NSImage(
            systemSymbolName: isActive ? "stop.fill" : "play.fill",
            accessibilityDescription: isActive ? "Stop" : "Run"
        )
        runItem.button?.toolTip = isActive ? "Stop" : "Run"
        runItem.button?.isEnabled = isActive || store.canRun
        runItem.button?.appearsDisabled = !(isActive || store.canRun)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    @objc private func toggleRun() {
        store.toggleRun()
    }
}

private struct MenuBarPopoverView: View {
    @Bindable var store: AppStore
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let project = store.project {
                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                popupRow(title: "Scheme") {
                    Picker("Scheme", selection: schemeSelection) {
                        if store.schemes.isEmpty {
                            Text(store.isLoadingSchemes ? "Finding Schemes…" : "No Schemes")
                                .tag(String?.none)
                        } else {
                            ForEach(store.schemes, id: \.self) { scheme in
                                Text(scheme).tag(String?.some(scheme))
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(store.schemes.isEmpty || store.phase.isActive || store.isLoadingSchemes)
                }

                popupRow(title: "Run Destination") {
                    Picker("Run Destination", selection: destinationSelection) {
                        if runnableDestinations.isEmpty {
                            Text(store.isLoadingDestinations ? "Finding Destinations…" : "No Destinations")
                                .tag(RunDestination?.none)
                        } else {
                            ForEach(runnableDestinations) { destination in
                                Text(destinationTitle(destination))
                                    .tag(RunDestination?.some(destination))
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(runnableDestinations.isEmpty || store.phase.isActive)
                }

                if case .failed(let message) = store.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }

                Divider()
                    .padding(.vertical, 6)
            }

            menuButton("Open…", shortcut: "⌘O") {
                store.chooseProject()
            }

            if store.recentProjects.isEmpty {
                menuRow("No Recents")
                    .foregroundStyle(.tertiary)
            } else {
                Menu {
                    ForEach(store.recentProjects) { project in
                        Button(project.name) {
                            store.openProject(at: project.url)
                        }
                    }
                    Divider()
                    Button("Clear", role: .destructive) {
                        showsClearConfirmation = true
                    }
                } label: {
                    menuRow("Recents", trailing: "chevron.right")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            Divider()
                .padding(.vertical, 6)

            menuButton("Quit", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.bottom, 8)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Clear Recents?", isPresented: $showsClearConfirmation) {
            Button("Clear", role: .destructive) {
                store.clearRecents()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes all projects from the Recents menu.")
        }
    }

    private var schemeSelection: Binding<String?> {
        Binding(
            get: { store.selectedScheme },
            set: { scheme in
                if let scheme {
                    store.selectScheme(scheme)
                }
            }
        )
    }

    private var destinationSelection: Binding<RunDestination?> {
        Binding(
            get: { store.selectedDestination },
            set: { destination in
                if let destination {
                    store.selectDestination(destination)
                }
            }
        )
    }

    private var runnableDestinations: [RunDestination] {
        store.destinations.filter(\.isRunnable)
    }

    private func destinationTitle(_ destination: RunDestination) -> String {
        let hasDuplicateName = runnableDestinations.filter { $0.name == destination.name }.count > 1
        return hasDuplicateName ? "\(destination.name) — \(destination.platform)" : destination.name
    }

    private func popupRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 125, alignment: .leading)
            content()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func menuButton(
        _ title: String,
        shortcut: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func menuRow(_ title: String, trailing systemImage: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .contentShape(.rect)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

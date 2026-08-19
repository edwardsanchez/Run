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
        popover.contentSize = NSSize(width: 380, height: 240)
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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 250),
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

struct MenuBarPopoverView: View {
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
                    .padding(.top, 13)
                    .padding(.bottom, 9)

                configurationMenus
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)

                if case .failed(let message) = store.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }

                Divider()
            }

            MenuActionRow(title: "Open…", shortcut: "⌘O") {
                store.chooseProject()
            }

            if store.recentProjects.isEmpty {
                MenuActionRow(title: "No Recents", isEnabled: false) { }
            } else {
                recentsMenu
            }

            Divider()

            MenuActionRow(title: "Quit", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 7)
        .frame(width: 380)
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

    private var configurationMenus: some View {
        HStack(spacing: 0) {
            schemeMenu

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 3)
                .accessibilityHidden(true)

            destinationMenu
        }
        .padding(3)
        .background(.quaternary.opacity(0.72), in: .rect(cornerRadius: 7))
    }

    private var schemeMenu: some View {
        Menu {
            Picker("Scheme", selection: schemeSelection) {
                ForEach(store.schemeDescriptors) { scheme in
                    Label(scheme.name, systemImage: scheme.symbolName)
                        .tag(String?.some(scheme.name))
                }
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            PathSegmentLabel(
                title: store.selectedScheme ?? loadingSchemeTitle,
                symbolName: store.selectedSchemeDescriptor?.symbolName ?? "gearshape"
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(store.schemes.isEmpty || store.phase.isActive)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Scheme")
        .accessibilityValue(store.selectedScheme ?? loadingSchemeTitle)
    }

    private var destinationMenu: some View {
        Menu {
            Picker("Run Destination", selection: destinationSelection) {
                ForEach(store.destinationGroups) { group in
                    Section(group.name) {
                        ForEach(group.destinations) { destination in
                            Label(destinationMenuTitle(destination), systemImage: destination.symbolName)
                                .tag(RunDestination?.some(destination))
                                .disabled(!destination.isRunnable)
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            PathSegmentLabel(
                title: store.selectedDestination?.name ?? loadingDestinationTitle,
                symbolName: store.selectedDestination?.symbolName ?? "desktopcomputer"
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(store.destinations.isEmpty || store.phase.isActive)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Run Destination")
        .accessibilityValue(store.selectedDestination?.name ?? loadingDestinationTitle)
    }

    private var recentsMenu: some View {
        Menu {
            ForEach(store.recentProjects) { project in
                Button {
                    store.openProject(at: project.url)
                } label: {
                    Label(project.name, systemImage: "hammer")
                }
            }
            Divider()
            Button("Clear…", role: .destructive) {
                showsClearConfirmation = true
            }
        } label: {
            HStack {
                Text("Recents")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 5)
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

    private func destinationMenuTitle(_ destination: RunDestination) -> String {
        guard destination.isSimulator, let osVersion = destination.osVersion else {
            return destination.name
        }
        return "\(destination.name) — \(osVersion)"
    }

    private var loadingSchemeTitle: String {
        store.isLoadingSchemes ? "Finding Schemes…" : "No Scheme"
    }

    private var loadingDestinationTitle: String {
        store.isLoadingDestinations ? "Finding Destinations…" : "No Destination"
    }
}

private struct PathSegmentLabel: View {
    let title: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 29)
        .contentShape(.rect)
    }
}

private struct MenuActionRow: View {
    let title: String
    var shortcut: String?
    var isEnabled = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(isHovered ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(.rect)
            .foregroundStyle(isEnabled ? (isHovered ? Color.white : Color.primary) : Color.secondary)
            .background(isHovered && isEnabled ? Color.accentColor : .clear, in: .rect(cornerRadius: 5))
            .padding(.horizontal, 5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }
}

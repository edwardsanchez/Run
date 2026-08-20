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
    @State private var showsDestinationPicker = false
    @State private var showsRecents = false

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

            MenuActionRow(title: "Open…") {
                store.chooseProject()
            }

            if store.recentProjects.isEmpty {
                MenuActionRow(title: "No Recents", isEnabled: false) { }
            } else {
                MenuActionRow(title: "Recents", trailingSymbol: "chevron.right") {
                    showsRecents.toggle()
                }
                .popover(isPresented: $showsRecents, arrowEdge: .top) {
                    RecentsPickerPopover(store: store, isPresented: $showsRecents)
                }
            }

            Divider()
                .padding(.vertical, 4)

            MenuActionRow(title: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 7)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var configurationMenus: some View {
        HStack(spacing: 0) {
            schemeMenu

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 3)
                .accessibilityHidden(true)

            destinationPickerButton
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

    private var destinationPickerButton: some View {
        Button {
            showsDestinationPicker.toggle()
        } label: {
            PathSegmentLabel(
                title: store.selectedDestination?.name ?? loadingDestinationTitle,
                symbolName: store.selectedDestination?.symbolName ?? "desktopcomputer"
            )
        }
        .buttonStyle(.plain)
        .disabled(store.destinations.isEmpty || store.phase.isActive)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Run Destination")
        .accessibilityValue(store.selectedDestination?.name ?? loadingDestinationTitle)
        .popover(isPresented: $showsDestinationPicker, arrowEdge: .top) {
            RunDestinationPickerPopover(store: store, isPresented: $showsDestinationPicker)
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

    private var loadingSchemeTitle: String {
        store.isLoadingSchemes ? "Finding Schemes…" : "No Scheme"
    }

    private var loadingDestinationTitle: String {
        store.isLoadingDestinations ? "Finding Destinations…" : "No Destination"
    }
}

private struct RunDestinationPickerPopover: View {
    @Bindable var store: AppStore
    @Binding var isPresented: Bool
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredGroups) { group in
                        Text(group.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 3)

                        ForEach(group.destinations) { destination in
                            DestinationSelectionRow(
                                title: displayTitle(for: destination),
                                symbolName: destination.symbolName,
                                version: destination.osVersion,
                                connectionSymbol: destination.connectionKind?.symbolName,
                                isSelected: destination == store.selectedDestination,
                                isEnabled: destination.isRunnable
                            ) {
                                store.selectDestination(destination)
                                isPresented = false
                            }
                            .help(destination.availabilityError ?? destination.name)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 500)
        }
        .frame(width: 430)
    }

    private var filteredGroups: [RunDestinationGroup] {
        guard !query.isEmpty else { return store.destinationGroups }
        return store.destinationGroups.compactMap { group in
            let destinations = group.destinations.filter { destination in
                destination.name.localizedStandardContains(query)
                    || destination.platform.localizedStandardContains(query)
                    || destination.osVersion?.localizedStandardContains(query) == true
            }
            return destinations.isEmpty ? nil : RunDestinationGroup(name: group.name, destinations: destinations)
        }
    }

    private func displayTitle(for destination: RunDestination) -> String {
        let duplicates = store.destinations.filter { $0.name == destination.name }
        guard duplicates.count > 1, let identifier = destination.identifier else {
            return destination.name
        }
        return "\(destination.name) (\(identifier))"
    }
}

private struct DestinationSelectionRow: View {
    let title: String
    let symbolName: String
    let version: String?
    let connectionSymbol: String?
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)

                Image(systemName: symbolName)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 16, height: 16)
                    .padding(.leading, 2)

                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 6)

                if let connectionSymbol {
                    Image(systemName: connectionSymbol)
                        .font(.system(size: 12))
                        .padding(.leading, 6)
                }

                Spacer(minLength: 10)

                if let version {
                    Text(version)
                        .foregroundStyle(isHovered ? Color.white.opacity(0.8) : Color.secondary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .contentShape(.rect)
            .foregroundStyle(rowForeground)
            .background(isHovered && isEnabled ? Color.accentColor : .clear, in: .rect(cornerRadius: 5))
            .padding(.horizontal, 5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowForeground: Color {
        if !isEnabled { return .secondary }
        return isHovered ? .white : .primary
    }
}

private struct RecentsPickerPopover: View {
    @Bindable var store: AppStore
    @Binding var isPresented: Bool
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(store.recentProjects) { project in
                MenuActionRow(title: project.name, trailingSymbol: "hammer") {
                    store.openProject(at: project.url)
                    isPresented = false
                }
                .help(project.url.path)
            }

            Divider()
                .padding(.vertical, 4)

            Button("Clear Recents…", role: .destructive) {
                showsClearConfirmation = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .padding(.top, 6)
        .frame(width: 280)
        .alert("Clear Recents?", isPresented: $showsClearConfirmation) {
            Button("Clear", role: .destructive) {
                store.clearRecents()
                isPresented = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes all projects from the Recents menu.")
        }
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
    var trailingSymbol: String?
    var isEnabled = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.caption.weight(.semibold))
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

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
        updateNameItem()
        updateRunItem()

        store.onChange = { [weak self] in
            self?.updateNameItem()
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

    private func updateNameItem() {
        let title = store.selectedScheme ?? "Run"
        nameItem.button?.title = title
        nameItem.button?.toolTip = title
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
    @State private var showsSchemePicker = false
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

            }

            ProjectOpenRow(showsDivider: store.project != nil) {
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
                .padding(.vertical, MenuLayout.standardSeparatorSpacing)

            MenuActionRow(title: "Quit", usesConcentricBottomCorners: true) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 7)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var configurationMenus: some View {
        HStack(spacing: 0) {
            schemePickerButton

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

    private var schemePickerButton: some View {
        Button {
            showsSchemePicker.toggle()
        } label: {
            PathSegmentLabel(
                title: store.selectedScheme ?? loadingSchemeTitle,
                symbolName: store.selectedSchemeDescriptor?.symbolName ?? "gearshape"
            )
        }
        .buttonStyle(.plain)
        .disabled(store.schemes.isEmpty || store.phase.isActive)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Scheme")
        .accessibilityValue(store.selectedScheme ?? loadingSchemeTitle)
        .popover(isPresented: $showsSchemePicker, arrowEdge: .top) {
            SchemePickerPopover(store: store, isPresented: $showsSchemePicker)
        }
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

    private var loadingSchemeTitle: String {
        store.isLoadingSchemes ? "Finding Schemes…" : "No Scheme"
    }

    private var loadingDestinationTitle: String {
        store.isLoadingDestinations ? "Finding Destinations…" : "No Destination"
    }
}

private struct ProjectOpenRow: View {
    let showsDivider: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Divider()
                    .padding(.bottom, MenuLayout.projectOpenSeparatorSpacing)
            }

            MenuActionRow(title: "Open…", action: action)
        }
    }
}

private struct SchemePickerPopover: View {
    @Bindable var store: AppStore
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var highlightedName: String?
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HighLevelFilterField(
                text: $query,
                isFocused: $isFilterFocused,
                handleKey: handleKeyPress
            )

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSchemes) { scheme in
                            PickerSelectionRow(
                                title: scheme.name,
                                symbolName: scheme.symbolName,
                                version: nil,
                                connectionSymbol: nil,
                                isSelected: scheme.name == store.selectedScheme,
                                isHighlighted: scheme.name == highlightedName,
                                isEnabled: true,
                                usesConcentricBottomCorners: MenuLayout.isBottomItem(
                                    scheme.id,
                                    lastID: filteredSchemes.last?.id
                                )
                            ) {
                                chooseScheme(scheme)
                            }
                            .id(scheme.name)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: MenuLayout.schemePickerListHeight(itemCount: filteredSchemes.count))
                .onChange(of: highlightedName) { _, name in
                    if let name {
                        proxy.scrollTo(name, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 320)
        .onAppear {
            highlightedName = store.selectedScheme ?? filteredSchemes.first?.name
            Task {
                await Task.yield()
                isFilterFocused = true
            }
        }
        .onChange(of: query) { _, _ in
            reconcileHighlight()
        }
    }

    private var filteredSchemes: [SchemeDescriptor] {
        guard !query.isEmpty else { return store.schemeDescriptors }
        return store.schemeDescriptors.filter { $0.name.localizedStandardContains(query) }
    }

    private func handleKeyPress(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .upArrow:
            moveHighlight(by: -1)
        case .downArrow:
            moveHighlight(by: 1)
        case .return:
            if let highlightedName {
                store.selectScheme(highlightedName)
                isPresented = false
            }
        default:
            return .ignored
        }
        return .handled
    }

    private func moveHighlight(by offset: Int) {
        let schemes = filteredSchemes
        guard !schemes.isEmpty else { return }
        let current = schemes.firstIndex { $0.name == highlightedName }
            ?? (offset > 0 ? -1 : schemes.count)
        let next = min(max(current + offset, 0), schemes.count - 1)
        highlightedName = schemes[next].name
    }

    private func reconcileHighlight() {
        if filteredSchemes.contains(where: { $0.name == highlightedName }) { return }
        highlightedName = filteredSchemes.first { $0.name == store.selectedScheme }?.name
            ?? filteredSchemes.first?.name
    }

    private func chooseScheme(_ scheme: SchemeDescriptor) {
        store.selectScheme(scheme.name)
        isPresented = false
    }
}

private struct RunDestinationPickerPopover: View {
    @Bindable var store: AppStore
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var highlightedID: String?
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HighLevelFilterField(
                text: $query,
                isFocused: $isFilterFocused,
                handleKey: handleKeyPress
            )

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredGroups) { group in
                            Text(group.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 3)
                                .frame(
                                    height: MenuLayout.destinationGroupHeaderHeight,
                                    alignment: .bottomLeading
                                )

                            ForEach(group.destinations) { destination in
                                PickerSelectionRow(
                                    title: displayTitle(for: destination),
                                    symbolName: destination.symbolName,
                                    version: destination.osVersion,
                                    connectionSymbol: destination.connectionKind?.symbolName,
                                    isSelected: destination == store.selectedDestination,
                                    isHighlighted: destination.id == highlightedID,
                                    isEnabled: destination.isRunnable,
                                    usesConcentricBottomCorners: MenuLayout.isBottomItem(
                                        destination.id,
                                        lastID: filteredGroups.last?.destinations.last?.id
                                    )
                                ) {
                                    store.selectDestination(destination)
                                    isPresented = false
                                }
                                .id(destination.id)
                                .help(destination.availabilityError ?? destination.name)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(
                    height: MenuLayout.destinationPickerListHeight(
                        groupCount: filteredGroups.count,
                        itemCount: filteredGroups.reduce(0) { $0 + $1.destinations.count }
                    )
                )
                .onChange(of: highlightedID) { _, identifier in
                    if let identifier {
                        proxy.scrollTo(identifier, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 430)
        .onAppear {
            highlightedID = store.selectedDestination?.id ?? selectableDestinations.first?.id
            Task {
                await Task.yield()
                isFilterFocused = true
            }
        }
        .onChange(of: query) { _, _ in
            reconcileHighlight()
        }
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

    private var selectableDestinations: [RunDestination] {
        filteredGroups.flatMap(\.destinations).filter(\.isRunnable)
    }

    private func handleKeyPress(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .upArrow:
            moveHighlight(by: -1)
        case .downArrow:
            moveHighlight(by: 1)
        case .return:
            if let destination = selectableDestinations.first(where: { $0.id == highlightedID }) {
                store.selectDestination(destination)
                isPresented = false
            }
        default:
            return .ignored
        }
        return .handled
    }

    private func moveHighlight(by offset: Int) {
        let destinations = selectableDestinations
        guard !destinations.isEmpty else { return }
        let current = destinations.firstIndex { $0.id == highlightedID }
            ?? (offset > 0 ? -1 : destinations.count)
        let next = min(max(current + offset, 0), destinations.count - 1)
        highlightedID = destinations[next].id
    }

    private func reconcileHighlight() {
        if selectableDestinations.contains(where: { $0.id == highlightedID }) { return }
        highlightedID = selectableDestinations.first { $0.id == store.selectedDestination?.id }?.id
            ?? selectableDestinations.first?.id
    }
}

private struct PickerSelectionRow: View {
    let title: String
    let symbolName: String
    let version: String?
    let connectionSymbol: String?
    let isSelected: Bool
    var isHighlighted = false
    let isEnabled: Bool
    var usesConcentricBottomCorners = false
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
                        .foregroundStyle(isActive ? Color.white.opacity(0.8) : Color.secondary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: MenuLayout.menuItemHeight)
            .contentShape(.rect)
            .foregroundStyle(rowForeground)
            .background {
                rowBackground
            }
            .padding(.horizontal, 5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowForeground: Color {
        if !isEnabled { return .secondary }
        return isActive ? .white : .primary
    }

    private var isActive: Bool { isHovered || isHighlighted }

    @ViewBuilder
    private var rowBackground: some View {
        let color = isActive && isEnabled ? Color.accentColor : Color.clear
        if usesConcentricBottomCorners {
            ConcentricRectangle(
                uniformBottomCorners: .concentric(
                    minimum: .fixed(MenuLayout.minimumConcentricCornerRadius)
                ),
                topLeadingCorner: .fixed(5),
                topTrailingCorner: .fixed(5)
            )
            .fill(color)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(color)
        }
    }
}

private struct HighLevelFilterField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let handleKey: (KeyEquivalent) -> KeyPress.Result

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)

            TextField("Filter", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
                    handleKey(press.key)
                }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.primary.opacity(0.075), in: Capsule())
        .padding(12)
    }
}

private struct RecentsPickerPopover: View {
    @Bindable var store: AppStore
    @Binding var isPresented: Bool
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(store.recentProjects) { project in
                MenuActionRow(
                    title: project.name,
                    trailingSymbol: "hammer",
                    usesConcentricTopCorners: MenuLayout.isTopItem(
                        project.id,
                        firstID: store.recentProjects.first?.id
                    )
                ) {
                    store.openProject(at: project.url)
                    isPresented = false
                }
                .help(project.url.path)
            }

            Divider()
                .padding(.vertical, MenuLayout.standardSeparatorSpacing)

            MenuActionRow(
                title: "Clear Recents…",
                usesConcentricBottomCorners: true,
                role: .destructive
            ) {
                showsClearConfirmation = true
            }
            .padding(.bottom, 6)
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
    var usesConcentricTopCorners = false
    var usesConcentricBottomCorners = false
    var role: ButtonRole?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                Spacer()
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: MenuLayout.menuItemHeight)
            .contentShape(.rect)
            .foregroundStyle(rowForeground)
            .background {
                rowBackground
            }
            .padding(.horizontal, 5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let color = isHovered && isEnabled ? Color.accentColor : Color.clear
        if usesConcentricTopCorners || usesConcentricBottomCorners {
            ConcentricRectangle(
                uniformTopCorners: usesConcentricTopCorners ? concentricCorner : .fixed(5),
                uniformBottomCorners: usesConcentricBottomCorners ? concentricCorner : .fixed(5)
            )
            .fill(color)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(color)
        }
    }

    private var concentricCorner: Edge.Corner.Style {
        .concentric(minimum: .fixed(MenuLayout.minimumConcentricCornerRadius))
    }

    private var rowForeground: Color {
        guard isEnabled else { return .secondary }
        if isHovered { return .white }
        return role == .destructive ? .red : .primary
    }
}

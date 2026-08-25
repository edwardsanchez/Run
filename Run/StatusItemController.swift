import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: AppStore
    private let nameItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let runItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let buildProgressIndicator = NSProgressIndicator()
    private var runItemTrackingArea: NSTrackingArea?
    private var isRunItemHovered = false
    private var canRevealBuildStop = false
    private var renderedRunPhase: RunPhase?
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
        configureRunItemTracking()
        configureBuildProgressIndicator()

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
        if store.phase == .building, renderedRunPhase != .building {
            canRevealBuildStop = !isRunItemHovered
        } else if store.phase != .building {
            canRevealBuildStop = false
        }

        let presentation = MenuLayout.runControlPresentation(
            phase: store.phase,
            isHovered: isRunItemHovered,
            canRevealBuildStop: canRevealBuildStop
        )
        let isActive = store.phase.isActive
        let label: String
        switch presentation {
        case .run:
            label = "Run"
            setRunItemImage(symbolName: "play.fill", accessibilityDescription: label)
        case .building:
            label = "Building…"
            runItem.button?.image = nil
            buildProgressIndicator.startAnimation(nil)
        case .stopBuilding:
            label = "Stop Building"
            setRunItemImage(symbolName: "stop.fill", accessibilityDescription: label)
        case .stop:
            label = "Stop"
            setRunItemImage(symbolName: "stop.fill", accessibilityDescription: label)
        }
        runItem.button?.toolTip = label
        runItem.button?.setAccessibilityLabel(label)
        runItem.button?.isEnabled = isActive || store.canRun
        runItem.button?.appearsDisabled = !(isActive || store.canRun)
        renderedRunPhase = store.phase
    }

    private func setRunItemImage(symbolName: String, accessibilityDescription: String) {
        buildProgressIndicator.stopAnimation(nil)
        runItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
    }

    private func configureBuildProgressIndicator() {
        guard let button = runItem.button else { return }
        buildProgressIndicator.style = .spinning
        buildProgressIndicator.controlSize = .small
        buildProgressIndicator.isDisplayedWhenStopped = false
        buildProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(buildProgressIndicator)
        NSLayoutConstraint.activate([
            buildProgressIndicator.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            buildProgressIndicator.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            buildProgressIndicator.widthAnchor.constraint(equalToConstant: 14),
            buildProgressIndicator.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    private func configureRunItemTracking() {
        guard let button = runItem.button else { return }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(trackingArea)
        runItemTrackingArea = trackingArea
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

    @objc private func mouseEntered(with event: NSEvent) {
        isRunItemHovered = true
        updateRunItem()
    }

    @objc private func mouseExited(with event: NSEvent) {
        isRunItemHovered = false
        if store.phase == .building {
            canRevealBuildStop = true
        }
        updateRunItem()
    }
}

private enum MainMenuSelectionID: Equatable {
    case open
    case recents
    case recent(String)
    case clearRecents
    case quit
}

private struct RecentsContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuBarPopoverView: View {
    @Bindable var store: AppStore
    @State private var showsSchemePicker = false
    @State private var showsDestinationPicker = false
    @State private var recentsState = RecentsAccordionState()
    @State private var menuSelection = MenuSelectionState<MainMenuSelectionID>()
    @State private var showsClearRecentsConfirmation = false
    @State private var mouseMovementGate = MouseMovementGate<CGPoint>()
    @State private var recentsContentHeight: CGFloat = 0
    @State private var isSchemePickerHovered = false
    @State private var isDestinationPickerHovered = false
    @State private var keyboardFocus = MenuKeyboardFocusState()
    @FocusState private var isMenuFocused: Bool

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

            ProjectOpenRow(
                showsDivider: store.project != nil,
                isHighlighted: menuSelection.selectedID == .open,
                isSelectionFocused: keyboardFocus.isMainMenuFocused,
                onMouseActivity: { trackMouse($0, over: .open) }
            ) {
                store.chooseProject()
            }

            if store.recentProjects.isEmpty {
                MenuActionRow(title: "No Recents", isEnabled: false) { }
            } else {
                MenuActionRow(
                    title: "Recents",
                    trailingSymbol: "chevron.right",
                    trailingSymbolRotation: recentsState.chevronRotation,
                    isHighlighted: menuSelection.selectedID == .recents,
                    isSelectionFocused: keyboardFocus.isMainMenuFocused,
                    onMouseActivity: { trackMouse($0, over: .recents) }
                ) {
                    toggleRecents()
                }

                maskedRecentsAccordion
            }

            Divider()
                .padding(.vertical, MenuLayout.standardSeparatorSpacing)

            MenuActionRow(
                title: "Quit",
                isHighlighted: menuSelection.selectedID == .quit,
                isSelectionFocused: keyboardFocus.isMainMenuFocused,
                usesConcentricBottomCorners: true,
                onMouseActivity: { trackMouse($0, over: .quit) }
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 7)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .focusable(keyboardFocus.isMainMenuFocused)
        .focused($isMenuFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return]) { press in
            handleMenuKeyPress(press.key)
        }
        .background {
            if keyboardFocus.isMainMenuFocused {
                MenuKeyboardFocusView(
                    claimsFirstResponder: true,
                    handleKey: handleMenuKeyPress
                )
                .frame(width: 1, height: 1)
            }
        }
        .onAppear {
            recentsState.reconcileDefaultExpansion(
                itemCount: store.recentProjects.count,
                projectIsOpen: store.project != nil
            )
        }
        .onChange(of: store.recentProjects.count) { _, count in
            recentsState.reconcile(itemCount: count)
            if !recentsState.isExpanded {
                if case .recent = menuSelection.selectedID {
                    menuSelection.selectFromKeyboard(nil)
                }
            }
        }
        .onChange(of: store.project) { _, project in
            withAnimation(.easeInOut(duration: 0.18)) {
                recentsState.reconcileDefaultExpansion(
                    itemCount: store.recentProjects.count,
                    projectIsOpen: project != nil
                )
            }
            if !recentsState.isExpanded, case .recent = menuSelection.selectedID {
                menuSelection.selectFromKeyboard(nil)
            }
        }
        .onChange(of: showsSchemePicker) { _, isPresented in
            updateKeyboardFocus(for: .schemePicker, isPresented: isPresented)
        }
        .onChange(of: showsDestinationPicker) { _, isPresented in
            updateKeyboardFocus(for: .destinationPicker, isPresented: isPresented)
        }
        .alert("Clear Recents?", isPresented: $showsClearRecentsConfirmation) {
            Button("Clear", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    recentsState.collapse()
                }
                menuSelection.selectFromKeyboard(nil)
                store.clearRecents()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes all projects from the Recents menu.")
        }
    }

    private var recentsAccordion: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.recentProjects.enumerated()), id: \.element.id) { index, project in
                let descriptor = store.recentSchemeDescriptor(for: project)
                MenuActionRow(
                    title: project.name,
                    leadingIconImage: store.recentSchemeIcon(for: project),
                    leadingSymbolName: descriptor?.symbolName ?? "app",
                    usesAppIconFallback: descriptor?.usesAppIconFallback ?? true,
                    trailingSymbol: MenuLayout.recentProjectTrailingSymbol,
                    contentLeadingIndent: MenuLayout.nestedMenuItemContentLeadingIndent,
                    isHighlighted: menuSelection.selectedID == .recent(project.id),
                    isSelectionFocused: keyboardFocus.isMainMenuFocused,
                    onMouseActivity: { trackMouse($0, over: .recent(project.id)) }
                ) {
                    chooseRecent(at: index)
                }
                .help(project.url.path)
            }

            Divider()
                .padding(.leading, 14)
                .padding(.vertical, MenuLayout.standardSeparatorSpacing)

            MenuActionRow(
                title: "Clear Recents…",
                contentLeadingIndent: MenuLayout.nestedMenuItemContentLeadingIndent,
                isHighlighted: menuSelection.selectedID == .clearRecents,
                isSelectionFocused: keyboardFocus.isMainMenuFocused,
                role: .destructive,
                onMouseActivity: { trackMouse($0, over: .clearRecents) }
            ) {
                showsClearRecentsConfirmation = true
            }
        }
    }

    private var maskedRecentsAccordion: some View {
        recentsAccordion
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RecentsContentHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            }
            .frame(
                height: recentsState.isExpanded ? recentsContentHeight : 0,
                alignment: .top
            )
            .clipped()
            .allowsHitTesting(recentsState.isExpanded)
            .accessibilityHidden(!recentsState.isExpanded)
            .onPreferenceChange(RecentsContentHeightPreferenceKey.self) { height in
                recentsContentHeight = height
            }
    }

    private func toggleRecents() {
        mouseMovementGate.recordCurrentPosition(NSEvent.mouseLocation)
        withAnimation(.easeInOut(duration: 0.18)) {
            recentsState.toggle(itemCount: store.recentProjects.count)
        }
        menuSelection.selectFromKeyboard(.recents)
        Task {
            await Task.yield()
            isMenuFocused = true
        }
    }

    private func handleMenuKeyPress(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .leftArrow:
            guard menuSelection.selectedID == .recents else { return .ignored }
            setRecentsExpanded(false)
        case .rightArrow:
            guard menuSelection.selectedID == .recents else { return .ignored }
            setRecentsExpanded(true)
        case .upArrow:
            moveMenuSelection(by: -1)
        case .downArrow:
            moveMenuSelection(by: 1)
        case .return:
            guard activateMenuSelection() else { return .ignored }
        default:
            return .ignored
        }
        return .handled
    }

    private func activateMenuSelection() -> Bool {
        switch menuSelection.selectedID {
        case .open:
            store.chooseProject()
        case .recents:
            toggleRecents()
        case .recent(let id):
            guard let index = store.recentProjects.firstIndex(where: { $0.id == id }) else {
                return false
            }
            chooseRecent(at: index)
        case .clearRecents:
            showsClearRecentsConfirmation = true
        case .quit:
            NSApplication.shared.terminate(nil)
        case nil:
            return false
        }
        return true
    }

    private func setRecentsExpanded(_ isExpanded: Bool) {
        guard recentsState.isExpanded != isExpanded else { return }
        mouseMovementGate.recordCurrentPosition(NSEvent.mouseLocation)
        withAnimation(.easeInOut(duration: 0.18)) {
            recentsState.moveHorizontally(
                by: isExpanded ? 1 : -1,
                itemCount: store.recentProjects.count
            )
        }
        menuSelection.selectFromKeyboard(.recents)
        isMenuFocused = true
    }

    private var keyboardMenuOrder: [MainMenuSelectionID] {
        [.open, .recents]
            + store.recentProjects.map { .recent($0.id) }
            + [.clearRecents, .quit]
    }

    private func moveMenuSelection(by offset: Int) {
        mouseMovementGate.recordCurrentPosition(NSEvent.mouseLocation)
        let fallback: MainMenuSelectionID = offset > 0 ? .recents : .open
        menuSelection.moveFromKeyboard(
            by: offset,
            through: keyboardMenuOrder,
            fallbackID: fallback
        )
    }

    private func trackMouse(_ isActive: Bool, over id: MainMenuSelectionID) {
        guard isActive else {
            menuSelection.clearMouseSelection(if: id)
            return
        }
        let location = NSEvent.mouseLocation
        guard mouseMovementGate.registerMovement(to: location) else { return }
        menuSelection.selectFromMouse(id)
        isMenuFocused = true
    }

    private func updateKeyboardFocus(
        for picker: MenuKeyboardFocusOwner,
        isPresented: Bool
    ) {
        if isPresented {
            return
        } else {
            keyboardFocus.dismiss(picker)
            guard keyboardFocus.isMainMenuFocused else { return }
            Task {
                await Task.yield()
                isMenuFocused = true
            }
        }
    }

    private func toggleSchemePicker() {
        showsDestinationPicker = false
        if showsSchemePicker {
            showsSchemePicker = false
        } else {
            keyboardFocus.present(.schemePicker)
            isMenuFocused = false
            showsSchemePicker = true
        }
    }

    private func toggleDestinationPicker() {
        showsSchemePicker = false
        if showsDestinationPicker {
            showsDestinationPicker = false
        } else {
            keyboardFocus.present(.destinationPicker)
            isMenuFocused = false
            showsDestinationPicker = true
        }
    }

    private func chooseRecent(at index: Int) {
        guard store.recentProjects.indices.contains(index) else { return }
        let project = store.recentProjects[index]
        withAnimation(.easeInOut(duration: 0.18)) {
            recentsState.collapse()
        }
        menuSelection.selectFromKeyboard(nil)
        store.openProject(at: project.url)
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

    @ViewBuilder
    private var schemePickerButton: some View {
        if MenuLayout.shouldOpenPicker(itemCount: store.schemeDescriptors.count) {
            Button(action: toggleSchemePicker) {
                PathSegmentLabel(
                    title: schemeTitle,
                    iconImage: store.selectedSchemeDescriptor.flatMap(store.schemeIcon(for:)),
                    symbolName: store.selectedSchemeDescriptor?.symbolName ?? "gearshape",
                    usesAppIconFallback: store.selectedSchemeDescriptor?.usesAppIconFallback ?? false,
                    presentation: schemePresentation,
                    showsMenuIndicator: true,
                    isHovered: isSchemePickerHovered,
                    isClickable: !store.phase.isActive
                )
            }
            .buttonStyle(.plain)
            .disabled(store.phase.isActive)
            .frame(maxWidth: .infinity)
            .onContinuousHover { phase in
                switch phase {
                case .active: isSchemePickerHovered = true
                case .ended: isSchemePickerHovered = false
                }
            }
            .accessibilityLabel("Scheme")
            .accessibilityValue(schemeTitle)
            .popover(isPresented: $showsSchemePicker, arrowEdge: .top) {
                SchemePickerPopover(store: store, isPresented: $showsSchemePicker)
            }
        } else {
            PathSegmentLabel(
                title: schemeTitle,
                iconImage: store.selectedSchemeDescriptor.flatMap(store.schemeIcon(for:)),
                symbolName: store.selectedSchemeDescriptor?.symbolName ?? "gearshape",
                usesAppIconFallback: store.selectedSchemeDescriptor?.usesAppIconFallback ?? false,
                presentation: schemePresentation,
                showsMenuIndicator: false,
                isHovered: false,
                isClickable: false
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scheme")
            .accessibilityValue(schemeTitle)
        }
    }

    @ViewBuilder
    private var destinationPickerButton: some View {
        if MenuLayout.shouldOpenPicker(itemCount: store.visibleDestinations.count) {
            Button(action: toggleDestinationPicker) {
                PathSegmentLabel(
                    title: destinationTitle,
                    symbolName: store.selectedDestination?.symbolName ?? "desktopcomputer",
                    presentation: destinationPresentation,
                    showsMenuIndicator: true,
                    isHovered: isDestinationPickerHovered,
                    isClickable: !store.phase.isActive
                )
            }
            .buttonStyle(.plain)
            .disabled(store.phase.isActive)
            .frame(maxWidth: .infinity)
            .onContinuousHover { phase in
                switch phase {
                case .active: isDestinationPickerHovered = true
                case .ended: isDestinationPickerHovered = false
                }
            }
            .accessibilityLabel("Run Destination")
            .accessibilityValue(destinationTitle)
            .popover(isPresented: $showsDestinationPicker, arrowEdge: .top) {
                RunDestinationPickerPopover(store: store, isPresented: $showsDestinationPicker)
            }
        } else {
            PathSegmentLabel(
                title: destinationTitle,
                symbolName: store.selectedDestination?.symbolName ?? "desktopcomputer",
                presentation: destinationPresentation,
                showsMenuIndicator: false,
                isHovered: false,
                isClickable: false
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Run Destination")
            .accessibilityValue(destinationTitle)
        }
    }

    private var schemePresentation: PickerSegmentPresentation {
        MenuLayout.pickerSegmentPresentation(
            isLoading: store.isLoadingSchemes,
            hasSelection: store.selectedScheme != nil
        )
    }

    private var destinationPresentation: PickerSegmentPresentation {
        MenuLayout.pickerSegmentPresentation(
            isLoading: store.isLoadingDestinations,
            hasSelection: store.selectedDestination != nil
        )
    }

    private var schemeTitle: String {
        schemePresentation == .loading ? "Loading…" : store.selectedScheme ?? "No Scheme"
    }

    private var destinationTitle: String {
        destinationPresentation == .loading ? "Loading…" : store.selectedDestination?.name ?? "No Destination"
    }
}

private struct ProjectOpenRow: View {
    let showsDivider: Bool
    var isHighlighted = false
    var isSelectionFocused = true
    var onMouseActivity: ((Bool) -> Void)?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Divider()
                    .padding(.bottom, MenuLayout.projectOpenSeparatorSpacing)
            }

            MenuActionRow(
                title: "Open…",
                isHighlighted: isHighlighted,
                isSelectionFocused: isSelectionFocused,
                usesConcentricTopCorners: MenuLayout.projectOpenUsesConcentricTopCorners(
                    showsDivider: showsDivider
                ),
                onMouseActivity: onMouseActivity,
                action: action
            )
        }
    }
}

private struct SchemePickerPopover: View {
    @Bindable var store: AppStore
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selection = MenuSelectionState<String>()
    @State private var mouseMovementGate = MouseMovementGate<CGPoint>()
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsFilter {
                FilterField(
                    text: $query,
                    isFocused: $isFilterFocused,
                    handleKey: handleKeyPress
                )

                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSchemes) { scheme in
                            PickerSelectionRow(
                                title: scheme.name,
                                iconImage: store.schemeIcon(for: scheme),
                                symbolName: scheme.symbolName,
                                usesAppIconFallback: scheme.usesAppIconFallback,
                                version: nil,
                                connectionSymbol: nil,
                                isSelected: scheme.name == store.selectedScheme,
                                isHighlighted: scheme.name == selection.selectedID,
                                isEnabled: true,
                                usesConcentricTopCorners: !showsFilter && MenuLayout.isTopItem(
                                    scheme.id,
                                    firstID: filteredSchemes.first?.id
                                ),
                                usesConcentricBottomCorners: MenuLayout.isBottomItem(
                                    scheme.id,
                                    lastID: filteredSchemes.last?.id
                                ),
                                onMouseActivity: { trackMouse($0, over: scheme.name) }
                            ) {
                                chooseScheme(scheme)
                            }
                            .id(scheme.name)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: MenuLayout.schemePickerListHeight(itemCount: filteredSchemes.count))
                .onChange(of: selection.selectedID) { _, name in
                    if let name {
                        proxy.scrollTo(name, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 320)
        .defaultFocus($isFilterFocused, showsFilter)
        .background {
            MenuKeyboardFocusView(
                claimsFirstResponder: !showsFilter,
                handleKey: handleKeyPress
            )
            .frame(width: 1, height: 1)
        }
        .onAppear {
            selection.selectFromKeyboard(store.selectedScheme ?? filteredSchemes.first?.name)
            if showsFilter {
                Task {
                    await Task.yield()
                    isFilterFocused = true
                }
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

    private var showsFilter: Bool {
        MenuLayout.shouldShowFilter(itemCount: store.schemeDescriptors.count)
    }

    private func handleKeyPress(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .upArrow:
            moveSelection(by: -1)
        case .downArrow:
            moveSelection(by: 1)
        case .return:
            if let selectedName = selection.selectedID {
                store.selectScheme(selectedName)
                isPresented = false
            }
        default:
            return .ignored
        }
        return .handled
    }

    private func moveSelection(by offset: Int) {
        let schemes = filteredSchemes
        guard !schemes.isEmpty else { return }
        mouseMovementGate.recordCurrentPosition(NSEvent.mouseLocation)
        let names = schemes.map(\.name)
        selection.moveFromKeyboard(
            by: offset,
            through: names,
            fallbackID: offset > 0 ? names.first : names.last
        )
    }

    private func reconcileHighlight() {
        if filteredSchemes.contains(where: { $0.name == selection.selectedID }) { return }
        selection.selectFromKeyboard(
            filteredSchemes.first { $0.name == store.selectedScheme }?.name
                ?? filteredSchemes.first?.name
        )
    }

    private func trackMouse(_ isActive: Bool, over name: String) {
        guard isActive else {
            selection.clearMouseSelection(if: name)
            return
        }
        let location = NSEvent.mouseLocation
        guard mouseMovementGate.registerMovement(to: location) else { return }
        selection.selectFromMouse(name)
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
    @State private var selection = MenuSelectionState<String>()
    @State private var mouseMovementGate = MouseMovementGate<CGPoint>()
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsFilter {
                FilterField(
                    text: $query,
                    isFocused: $isFilterFocused,
                    handleKey: handleKeyPress
                )

                Divider()
            }

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
                                    isHighlighted: destination.id == selection.selectedID,
                                    isEnabled: destination.isRunnable,
                                    usesConcentricBottomCorners: MenuLayout.isBottomItem(
                                        destination.id,
                                        lastID: filteredGroups.last?.destinations.last?.id
                                    ),
                                    onMouseActivity: { trackMouse($0, over: destination.id) }
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
                .onChange(of: selection.selectedID) { _, identifier in
                    if let identifier {
                        proxy.scrollTo(identifier, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 430)
        .defaultFocus($isFilterFocused, showsFilter)
        .background {
            MenuKeyboardFocusView(
                claimsFirstResponder: !showsFilter,
                handleKey: handleKeyPress
            )
            .frame(width: 1, height: 1)
        }
        .onAppear {
            selection.selectFromKeyboard(
                store.selectedDestination?.id ?? selectableDestinations.first?.id
            )
            if showsFilter {
                Task {
                    await Task.yield()
                    isFilterFocused = true
                }
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

    private var showsFilter: Bool {
        MenuLayout.shouldShowFilter(itemCount: store.visibleDestinations.count)
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
            moveSelection(by: -1)
        case .downArrow:
            moveSelection(by: 1)
        case .return:
            if let destination = selectableDestinations.first(where: { $0.id == selection.selectedID }) {
                store.selectDestination(destination)
                isPresented = false
            }
        default:
            return .ignored
        }
        return .handled
    }

    private func moveSelection(by offset: Int) {
        let destinations = selectableDestinations
        guard !destinations.isEmpty else { return }
        mouseMovementGate.recordCurrentPosition(NSEvent.mouseLocation)
        let identifiers = destinations.map(\.id)
        selection.moveFromKeyboard(
            by: offset,
            through: identifiers,
            fallbackID: offset > 0 ? identifiers.first : identifiers.last
        )
    }

    private func reconcileHighlight() {
        if selectableDestinations.contains(where: { $0.id == selection.selectedID }) { return }
        selection.selectFromKeyboard(
            selectableDestinations.first { $0.id == store.selectedDestination?.id }?.id
                ?? selectableDestinations.first?.id
        )
    }

    private func trackMouse(_ isActive: Bool, over id: String) {
        guard isActive else {
            selection.clearMouseSelection(if: id)
            return
        }
        let location = NSEvent.mouseLocation
        guard mouseMovementGate.registerMovement(to: location) else { return }
        selection.selectFromMouse(id)
    }
}

private struct PickerSelectionRow: View {
    let title: String
    var iconImage: NSImage? = nil
    let symbolName: String
    var usesAppIconFallback = false
    let version: String?
    let connectionSymbol: String?
    let isSelected: Bool
    var isHighlighted = false
    let isEnabled: Bool
    var usesConcentricTopCorners = false
    var usesConcentricBottomCorners = false
    var onMouseActivity: ((Bool) -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)

                PickerIconView(
                    image: iconImage,
                    symbolName: symbolName,
                    usesAppIconFallback: usesAppIconFallback,
                    color: isActive ? .white : .blue
                )
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
        .onContinuousHover { phase in
            switch phase {
            case .active:
                onMouseActivity?(true)
            case .ended:
                onMouseActivity?(false)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowForeground: Color {
        if !isEnabled { return .secondary }
        return isActive ? .white : .primary
    }

    private var isActive: Bool { isHighlighted }

    @ViewBuilder
    private var rowBackground: some View {
        let color = isActive && isEnabled ? Color.accentColor : Color.clear
        if usesConcentricTopCorners || usesConcentricBottomCorners {
            let concentricCorner = Edge.Corner.Style.concentric(
                minimum: .fixed(MenuLayout.minimumConcentricCornerRadius)
            )
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
}

private struct MenuKeyboardFocusView: NSViewRepresentable {
    let claimsFirstResponder: Bool
    let handleKey: (KeyEquivalent) -> KeyPress.Result

    func makeNSView(context: Context) -> MenuKeyboardFocusNSView {
        MenuKeyboardFocusNSView(
            claimsFirstResponder: claimsFirstResponder,
            handleKey: handleKey
        )
    }

    func updateNSView(_ view: MenuKeyboardFocusNSView, context: Context) {
        view.claimsFirstResponder = claimsFirstResponder
        view.handleKey = handleKey
        if claimsFirstResponder {
            view.scheduleFirstResponderClaim()
        }
    }

    static func dismantleNSView(_ view: MenuKeyboardFocusNSView, coordinator: ()) {
        view.tearDown()
    }
}

private final class MenuKeyboardFocusNSView: NSView {
    var claimsFirstResponder: Bool
    var handleKey: (KeyEquivalent) -> KeyPress.Result
    private var keyMonitor: Any?

    init(
        claimsFirstResponder: Bool,
        handleKey: @escaping (KeyEquivalent) -> KeyPress.Result
    ) {
        self.claimsFirstResponder = claimsFirstResponder
        self.handleKey = handleKey
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { claimsFirstResponder }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeKeyMonitor()
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            }
        }
        if claimsFirstResponder {
            scheduleFirstResponderClaim()
        }
    }

    @objc private func windowDidBecomeKey() {
        scheduleFirstResponderClaim()
    }

    func scheduleFirstResponderClaim() {
        Task { @MainActor [weak self] in
            await Task.yield()
            await Task.yield()
            guard let self, self.claimsFirstResponder,
                  let window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if !handle(event) {
            super.keyDown(with: event)
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let key: KeyEquivalent
        switch event.keyCode {
        case 123:
            key = .leftArrow
        case 124:
            key = .rightArrow
        case 125:
            key = .downArrow
        case 126:
            key = .upArrow
        case 36, 76:
            key = .return
        default:
            return false
        }

        return handleKey(key) == .handled
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    func tearDown() {
        removeKeyMonitor()
        NotificationCenter.default.removeObserver(self)
    }
}

private struct FilterField: View {
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

private struct PathSegmentLabel: View {
    let title: String
    var iconImage: NSImage? = nil
    let symbolName: String
    var usesAppIconFallback = false
    let presentation: PickerSegmentPresentation
    let showsMenuIndicator: Bool
    let isHovered: Bool
    let isClickable: Bool

    var body: some View {
        HStack(spacing: 6) {
            if presentation == .loading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                PickerIconView(
                    image: iconImage,
                    symbolName: symbolName,
                    usesAppIconFallback: usesAppIconFallback,
                    color: .secondary
                )
            }
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 29)
        .background(
            Color.primary.opacity(
                MenuLayout.pickerHoverOpacity(
                    isClickable: isClickable,
                    isHovered: isHovered
                )
            ),
            in: .rect(cornerRadius: 5)
        )
        .contentShape(.rect)
    }
}

private struct PickerIconView: View {
    let image: NSImage?
    let symbolName: String
    let usesAppIconFallback: Bool
    let color: Color

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if usesAppIconFallback {
                Image("AppFallback")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

private struct MenuActionRow: View {
    let title: String
    var leadingIconImage: NSImage? = nil
    var leadingSymbolName: String? = nil
    var usesAppIconFallback = false
    var trailingSymbol: String?
    var trailingSymbolRotation = 0.0
    var contentLeadingIndent = 0.0
    var isEnabled = true
    var isHighlighted = false
    var isSelectionFocused = true
    var usesConcentricTopCorners = false
    var usesConcentricBottomCorners = false
    var role: ButtonRole?
    var onMouseActivity: ((Bool) -> Void)?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 0) {
                if leadingIconImage != nil || leadingSymbolName != nil {
                    PickerIconView(
                        image: leadingIconImage,
                        symbolName: leadingSymbolName ?? "app",
                        usesAppIconFallback: usesAppIconFallback,
                        color: isFocusedSelection ? .white : .blue
                    )

                    Text(title)
                        .padding(.leading, 6)
                } else {
                    Text(title)
                }
                Spacer()
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(trailingSymbolRotation))
                }
            }
            .padding(.leading, 10 + contentLeadingIndent)
            .padding(.trailing, 10)
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
        .onContinuousHover { phase in
            switch phase {
            case .active:
                onMouseActivity?(true)
            case .ended:
                onMouseActivity?(false)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let color = selectionBackground
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
        if isFocusedSelection { return .white }
        return role == .destructive ? .red : .primary
    }

    private var isFocusedSelection: Bool {
        isHighlighted && isSelectionFocused
    }

    private var selectionBackground: Color {
        guard isHighlighted, isEnabled else { return .clear }
        return isSelectionFocused
            ? .accentColor
            : .primary.opacity(MenuLayout.unfocusedSelectionOpacity)
    }
}

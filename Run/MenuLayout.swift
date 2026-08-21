import Foundation

enum MenuLayout {
    static let standardSeparatorSpacing = 4.0
    static let projectOpenSeparatorSpacing = standardSeparatorSpacing
    static let projectOpenDividerRemainsVisible = true
    static let bottomMenuItemUsesConcentricCorners = true
    static let menuItemHeight = 30.0
    static let pickerContentVerticalPadding = 8.0
    static let destinationGroupHeaderHeight = 26.0
    static let schemePickerMaximumListHeight = 360.0
    static let destinationPickerMaximumListHeight = 500.0
    static let minimumConcentricCornerRadius = menuItemHeight / 2
    static let nestedMenuItemContentLeadingIndent = 14.0
    static let recentProjectTrailingSymbol: String? = nil
    static let filterMinimumItemCount = 6
    static let recentsChevronCollapsedRotation = 0.0
    static let recentsChevronExpandedRotation = 90.0

    static func schemePickerListHeight(itemCount: Int) -> Double {
        min(
            Double(max(itemCount, 0)) * menuItemHeight + pickerContentVerticalPadding,
            schemePickerMaximumListHeight
        )
    }

    static func destinationPickerListHeight(groupCount: Int, itemCount: Int) -> Double {
        min(
            Double(max(groupCount, 0)) * destinationGroupHeaderHeight
                + Double(max(itemCount, 0)) * menuItemHeight
                + pickerContentVerticalPadding,
            destinationPickerMaximumListHeight
        )
    }

    static func shouldShowFilter(itemCount: Int) -> Bool {
        itemCount >= filterMinimumItemCount
    }

    static func shouldOpenPicker(itemCount: Int) -> Bool {
        itemCount > 1
    }

    static func pickerHoverOpacity(isClickable: Bool, isHovered: Bool) -> Double {
        isClickable && isHovered ? 0.1 : 0
    }

    static func projectOpenUsesConcentricTopCorners(showsDivider: Bool) -> Bool {
        !showsDivider
    }

    static func isTopItem<ID: Equatable>(_ id: ID, firstID: ID?) -> Bool {
        id == firstID
    }

    static func isBottomItem<ID: Equatable>(_ id: ID, lastID: ID?) -> Bool {
        id == lastID
    }

    static func runControlPresentation(
        phase: RunPhase,
        isHovered: Bool,
        canRevealBuildStop: Bool
    ) -> RunControlPresentation {
        switch phase {
        case .building:
            isHovered && canRevealBuildStop ? .stopBuilding : .building
        case .running, .stopping:
            .stop
        default:
            .run
        }
    }
}

struct RecentsAccordionState: Equatable {
    private(set) var isExpanded = false

    mutating func toggle(itemCount: Int) {
        if isExpanded {
            collapse()
        } else {
            expand(itemCount: itemCount)
        }
    }

    mutating func expand(itemCount: Int) {
        guard itemCount > 0 else { return }
        isExpanded = true
    }

    mutating func collapse() {
        isExpanded = false
    }

    mutating func moveHorizontally(by offset: Int, itemCount: Int) {
        if offset > 0 {
            expand(itemCount: itemCount)
        } else if offset < 0 {
            collapse()
        }
    }

    mutating func reconcile(itemCount: Int) {
        guard itemCount > 0 else {
            collapse()
            return
        }
    }

    var chevronRotation: Double {
        isExpanded
            ? MenuLayout.recentsChevronExpandedRotation
            : MenuLayout.recentsChevronCollapsedRotation
    }
}

enum MenuSelectionSource: Equatable {
    case keyboard
    case mouse
}

struct MenuSelectionState<ID: Equatable>: Equatable {
    private(set) var selectedID: ID?
    private(set) var source: MenuSelectionSource?

    mutating func selectFromKeyboard(_ id: ID?) {
        selectedID = id
        source = id == nil ? nil : .keyboard
    }

    mutating func selectFromMouse(_ id: ID) {
        selectedID = id
        source = .mouse
    }

    mutating func clearMouseSelection(if id: ID) {
        guard source == .mouse, selectedID == id else { return }
        selectedID = nil
        source = nil
    }

    mutating func moveFromKeyboard(
        by offset: Int,
        through orderedIDs: [ID],
        fallbackID: ID?
    ) {
        guard !orderedIDs.isEmpty else {
            selectFromKeyboard(nil)
            return
        }
        guard let selectedID, let current = orderedIDs.firstIndex(of: selectedID) else {
            selectFromKeyboard(fallbackID ?? orderedIDs[0])
            return
        }
        let next = min(max(current + offset, 0), orderedIDs.count - 1)
        selectFromKeyboard(orderedIDs[next])
    }
}

struct MouseMovementGate<Position: Equatable>: Equatable {
    private(set) var lastPosition: Position?

    mutating func recordCurrentPosition(_ position: Position) {
        lastPosition = position
    }

    mutating func registerMovement(to position: Position) -> Bool {
        guard position != lastPosition else { return false }
        lastPosition = position
        return true
    }
}

enum RunControlPresentation: Equatable {
    case run
    case building
    case stopBuilding
    case stop
}

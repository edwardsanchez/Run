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
    private(set) var highlightedIndex: Int?

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
        highlightedIndex = 0
    }

    mutating func collapse() {
        isExpanded = false
        highlightedIndex = nil
    }

    mutating func moveHighlight(by offset: Int, itemCount: Int) {
        guard isExpanded, itemCount > 0 else { return }
        let current = highlightedIndex ?? (offset > 0 ? -1 : itemCount)
        highlightedIndex = min(max(current + offset, 0), itemCount - 1)
    }

    mutating func reconcile(itemCount: Int) {
        guard itemCount > 0 else {
            collapse()
            return
        }
        guard isExpanded else { return }
        highlightedIndex = min(highlightedIndex ?? 0, itemCount - 1)
    }

    var chevronRotation: Double {
        isExpanded
            ? MenuLayout.recentsChevronExpandedRotation
            : MenuLayout.recentsChevronCollapsedRotation
    }
}

enum RunControlPresentation: Equatable {
    case run
    case building
    case stopBuilding
    case stop
}

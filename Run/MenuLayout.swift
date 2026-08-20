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
}

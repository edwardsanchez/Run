import Testing
@testable import RunCore

struct MenuLayoutTests {
    @Test func openKeepsItsDividerAndUsesStandardSectionSpacing() {
        #expect(MenuLayout.projectOpenDividerRemainsVisible)
        #expect(MenuLayout.projectOpenSeparatorSpacing > 0)
        #expect(MenuLayout.projectOpenSeparatorSpacing == MenuLayout.standardSeparatorSpacing)
    }

    @Test func onlyPopoverEdgeItemsUseConcentricCorners() {
        #expect(MenuLayout.bottomMenuItemUsesConcentricCorners)
        #expect(MenuLayout.minimumConcentricCornerRadius == MenuLayout.menuItemHeight / 2)
        #expect(MenuLayout.isTopItem("first", firstID: "first"))
        #expect(!MenuLayout.isTopItem("last", firstID: "first"))
        #expect(!MenuLayout.isTopItem("only", firstID: String?.none))
        #expect(MenuLayout.isBottomItem("last", lastID: "last"))
        #expect(!MenuLayout.isBottomItem("first", lastID: "last"))
        #expect(!MenuLayout.isBottomItem("only", lastID: String?.none))
    }

    @Test func pickerListsFitTheirResultsUntilTheyReachTheirMaximumHeight() {
        #expect(MenuLayout.schemePickerListHeight(itemCount: 0) == 8)
        #expect(MenuLayout.schemePickerListHeight(itemCount: 1) == 38)
        #expect(MenuLayout.schemePickerListHeight(itemCount: 100) == 360)

        #expect(MenuLayout.destinationPickerListHeight(groupCount: 1, itemCount: 1) == 64)
        #expect(MenuLayout.destinationPickerListHeight(groupCount: 2, itemCount: 3) == 150)
        #expect(MenuLayout.destinationPickerListHeight(groupCount: 10, itemCount: 100) == 500)
    }

    @Test func runControlShowsBuildProgressUntilStopIsDeliberatelyRevealed() {
        #expect(MenuLayout.runControlPresentation(
            phase: .building,
            isHovered: false,
            canRevealBuildStop: false
        ) == .building)
        #expect(MenuLayout.runControlPresentation(
            phase: .building,
            isHovered: true,
            canRevealBuildStop: false
        ) == .building)
        #expect(MenuLayout.runControlPresentation(
            phase: .building,
            isHovered: true,
            canRevealBuildStop: true
        ) == .stopBuilding)
        #expect(MenuLayout.runControlPresentation(
            phase: .building,
            isHovered: false,
            canRevealBuildStop: true
        ) == .building)
        #expect(MenuLayout.runControlPresentation(
            phase: .running,
            isHovered: false,
            canRevealBuildStop: false
        ) == .stop)
        #expect(MenuLayout.runControlPresentation(
            phase: .idle,
            isHovered: true,
            canRevealBuildStop: true
        ) == .run)
    }
}

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

    @Test func pickerFilterAppearsOnlyWhenAListHasMoreThanFiveItems() {
        #expect(!MenuLayout.shouldShowFilter(itemCount: 0))
        #expect(!MenuLayout.shouldShowFilter(itemCount: 5))
        #expect(MenuLayout.shouldShowFilter(itemCount: 6))
    }

    @Test func pickerOpensOnlyWhenThereIsMoreThanOneChoice() {
        #expect(!MenuLayout.shouldOpenPicker(itemCount: 0))
        #expect(!MenuLayout.shouldOpenPicker(itemCount: 1))
        #expect(MenuLayout.shouldOpenPicker(itemCount: 2))
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

    @Test func recentsAccordionExpandsAndReversesOnSecondToggle() {
        var state = RecentsAccordionState()

        state.toggle(itemCount: 5)
        #expect(state.isExpanded)
        #expect(state.chevronRotation == MenuLayout.recentsChevronExpandedRotation)

        state.toggle(itemCount: 5)
        #expect(!state.isExpanded)
        #expect(state.chevronRotation == MenuLayout.recentsChevronCollapsedRotation)
    }

    @Test func keyboardNavigationOwnsTheOnlySelectionUntilTheMouseMoves() {
        var selection = MenuSelectionState<String>()
        selection.selectFromMouse("Recents")
        #expect(selection.selectedID == "Recents")
        #expect(selection.source == .mouse)

        selection.selectFromKeyboard("First Recent")
        #expect(selection.selectedID == "First Recent")
        #expect(selection.source == .keyboard)

        selection.clearMouseSelection(if: "Recents")
        #expect(selection.selectedID == "First Recent")

        selection.selectFromMouse("Open")
        #expect(selection.selectedID == "Open")
        #expect(selection.source == .mouse)
    }

    @Test func arrowNavigationStealsSelectionAndMovesThroughOneOrderedMenu() {
        var selection = MenuSelectionState<String>()
        let items = ["Open", "First Recent", "Second Recent", "Clear", "Quit"]

        selection.selectFromMouse("Open")
        selection.moveFromKeyboard(by: 1, through: items, fallbackID: "First Recent")
        #expect(selection.selectedID == "First Recent")
        #expect(selection.source == .keyboard)

        selection.moveFromKeyboard(by: 1, through: items, fallbackID: "First Recent")
        #expect(selection.selectedID == "Second Recent")
        selection.moveFromKeyboard(by: -1, through: items, fallbackID: "First Recent")
        #expect(selection.selectedID == "First Recent")
    }

    @Test func staticMouseDoesNotReclaimSelectionUntilItsPositionChanges() {
        var gate = MouseMovementGate<String>()

        gate.recordCurrentPosition("over Recents")
        let staticRecents = gate.registerMovement(to: "over Recents")
        let movedToOpen = gate.registerMovement(to: "over Open")
        let staticOpen = gate.registerMovement(to: "over Open")

        #expect(!staticRecents)
        #expect(movedToOpen)
        #expect(!staticOpen)
    }

    @Test func recentsAccordionDoesNotOpenWithoutItemsAndClosesWhenItemsDisappear() {
        var state = RecentsAccordionState()
        state.expand(itemCount: 0)
        #expect(!state.isExpanded)

        state.expand(itemCount: 2)
        state.reconcile(itemCount: 0)
        #expect(!state.isExpanded)
    }
}

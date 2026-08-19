import Foundation

struct MenuContent: Equatable {
    let projectName: String?
    let selectedSchemeName: String?
    let selectedDestinationName: String?
    let recentProjectNames: [String]

    init(
        projectName: String? = nil,
        selectedSchemeName: String? = nil,
        selectedDestinationName: String? = nil,
        recentProjectNames: [String]
    ) {
        self.projectName = projectName
        self.selectedSchemeName = selectedSchemeName
        self.selectedDestinationName = selectedDestinationName
        self.recentProjectNames = recentProjectNames
    }

    var hasRecents: Bool { !recentProjectNames.isEmpty }
    var recentsPlaceholder: String? { hasRecents ? nil : "No Recents" }

    var topLevelTitles: [String] {
        var titles: [String] = []
        if let projectName {
            titles += [
                projectName,
                "Scheme: \(selectedSchemeName ?? "Choose…")",
                "Run Destination: \(selectedDestinationName ?? "Choose…")",
                "—",
            ]
        }
        titles += ["Open…", hasRecents ? "Recents" : "No Recents", "—", "Quit"]
        return titles
    }
}

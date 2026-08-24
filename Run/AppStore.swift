import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppStore {
    private(set) var project: XcodeProject?
    private(set) var schemes: [String] = []
    private(set) var schemeDescriptors: [SchemeDescriptor] = []
    private(set) var destinations: [RunDestination] = []
    private(set) var recentProjects: [XcodeProject]
    private(set) var phase: RunPhase = .idle
    private(set) var selectedScheme: String?
    private(set) var selectedDestination: RunDestination?
    private(set) var isLoadingSchemes = false
    private(set) var isLoadingDestinations = false
    private(set) var recentDestinationIDs: [String] = []
    private(set) var schemeIconImages: [String: NSImage] = [:]
    private(set) var recentSchemeDescriptors: [String: SchemeDescriptor] = [:]
    private(set) var recentSchemeIconImages: [String: NSImage] = [:]

    @ObservationIgnored var onChange: (() -> Void)?
    private let client: XcodeClient
    private let metadataClient: XcodeClient
    private let recentsStore: RecentProjectsPersisting
    private let selectionStore: SelectionStore
    private let schemeIconProvider: SchemeIconProvider
    private var operation: Task<Void, Never>?
    private var schemeIconOperation: Task<Void, Never>?
    private var recentSchemeIconOperation: Task<Void, Never>?
    private var launchContext: LaunchContext?
    private var schemeDescriptorsByProject: [String: [SchemeDescriptor]] = [:]

    init(
        client: XcodeClient,
        metadataClient: XcodeClient,
        recentsStore: RecentProjectsPersisting,
        selectionStore: SelectionStore,
        schemeIconProvider: SchemeIconProvider
    ) {
        self.client = client
        self.metadataClient = metadataClient
        self.recentsStore = recentsStore
        self.selectionStore = selectionStore
        self.schemeIconProvider = schemeIconProvider
        let loadedProjects = recentsStore.load()
        let existingProjects = loadedProjects.filter {
            FileManager.default.fileExists(atPath: $0.url.path)
        }
        recentProjects = RecentProjectsPolicy.limited(existingProjects)
        if recentProjects != loadedProjects {
            recentsStore.save(recentProjects)
        }
        refreshRecentSchemeIcons()
    }

    convenience init() {
        self.init(
            client: XcodeClient(),
            metadataClient: XcodeClient(),
            recentsStore: UserDefaultsRecentProjectsStore(),
            selectionStore: SelectionStore(),
            schemeIconProvider: SchemeIconProvider()
        )
    }

    var canRun: Bool {
        project != nil && selectedScheme != nil && selectedDestination?.isRunnable == true && !phase.isActive
    }

    var selectedSchemeDescriptor: SchemeDescriptor? {
        guard let selectedScheme else { return nil }
        return schemeDescriptors.first { $0.name == selectedScheme }
    }

    func schemeIcon(for descriptor: SchemeDescriptor) -> NSImage? {
        schemeIconImages[descriptor.id]
    }

    func recentSchemeDescriptor(for project: XcodeProject) -> SchemeDescriptor? {
        recentSchemeDescriptors[project.id]
    }

    func recentSchemeIcon(for project: XcodeProject) -> NSImage? {
        recentSchemeIconImages[project.id]
    }

    var destinationGroups: [RunDestinationGroup] {
        XcodeOutputParser.runningDestinationGroups(
            from: destinations,
            recentDestinationIDs: recentDestinationIDs
        )
    }

    var visibleDestinations: [RunDestination] {
        destinationGroups.flatMap(\.destinations)
    }

    var menuContent: MenuContent {
        MenuContent(
            projectName: project?.name,
            selectedSchemeName: selectedScheme,
            selectedDestinationName: selectedDestination?.name,
            recentProjectNames: recentProjects.map(\.name)
        )
    }

    func chooseProject() {
        NSApplication.shared.activate()
        let panel = NSOpenPanel()
        panel.title = "Open Xcode Project"
        panel.message = "Choose an Xcode project or workspace to run."
        panel.prompt = "Open"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.xcodeProject, .xcodeWorkspace]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        guard let project = XcodeProject(url: url) else {
            setPhase(.failed(RunError.invalidProject.localizedDescription))
            return
        }

        let savedScheme = selectionStore.scheme(for: project)
        let savedDestinationID = selectionStore.destinationID(for: project)
        let previousLaunchContext = launchContext
        launchContext = nil
        operation?.cancel()
        client.cancelActiveCommand()
        self.project = project
        let localSchemeDescriptors = XcodeOutputParser.localSchemeDescriptors(in: project)
        let localSchemes = localSchemeDescriptors.map(\.name)
        schemes = localSchemes
        schemeDescriptors = localSchemeDescriptors
        refreshSchemeIcons(for: project, descriptors: localSchemeDescriptors)
        destinations = []
        selectedScheme = savedScheme.flatMap { localSchemes.contains($0) ? $0 : nil }
            ?? (localSchemes.count == 1 ? localSchemes[0] : nil)
        selectedDestination = nil
        recentDestinationIDs = selectedScheme.map {
            selectionStore.recentDestinationIDs(for: project, scheme: $0)
        } ?? []
        isLoadingSchemes = true
        isLoadingDestinations = true
        addRecent(project)
        setPhase(.idle)

        operation = Task {
            try? await client.stop(previousLaunchContext)
            guard !Task.isCancelled else { return }
            do {
                let allDiscoveredSchemes = try await client.schemes(for: project)
                guard !Task.isCancelled, self.project == project else { return }
                let discoveredSchemes = XcodeOutputParser.userSchemes(
                    discovered: allDiscoveredSchemes,
                    local: localSchemes
                )
                schemes = discoveredSchemes
                schemeDescriptors = try await client.schemeDescriptors(
                    for: project,
                    schemes: discoveredSchemes,
                    fileBackedDescriptors: localSchemeDescriptors
                )
                guard !Task.isCancelled, self.project == project else { return }
                schemeDescriptorsByProject[project.id] = schemeDescriptors
                refreshSchemeIcons(for: project, descriptors: schemeDescriptors)
                if let savedScheme, discoveredSchemes.contains(savedScheme) {
                    selectedScheme = savedScheme
                } else if discoveredSchemes.count == 1 {
                    selectedScheme = discoveredSchemes[0]
                } else {
                    selectedScheme = XcodeOutputParser.preferredScheme(
                        in: project,
                        availableSchemes: discoveredSchemes
                    )
                }
                isLoadingSchemes = false
                recentDestinationIDs = selectedScheme.map {
                    selectionStore.recentDestinationIDs(for: project, scheme: $0)
                } ?? []
                notifyChange()

                guard let selectedScheme else { throw RunError.noSchemes }
                let discoveredDestinations = try await client.destinations(
                    for: project,
                    scheme: selectedScheme
                )
                guard !Task.isCancelled, self.project == project, self.selectedScheme == selectedScheme else { return }
                destinations = discoveredDestinations
                selectedDestination = await client.preferredDestination(
                    in: discoveredDestinations,
                    savedDestinationID: savedDestinationID
                )
                isLoadingDestinations = false
                if savedDestinationID != nil, let selectedDestination {
                    rememberDestination(selectedDestination)
                }
                persistSelection()
                refreshRecentSchemeIcons()
                notifyChange()
            } catch {
                guard !Task.isCancelled else { return }
                isLoadingSchemes = false
                isLoadingDestinations = false
                setPhase(.failed(error.localizedDescription))
            }
        }
    }

    func clearRecents() {
        recentProjects = []
        recentSchemeDescriptors = [:]
        recentSchemeIconImages = [:]
        recentSchemeIconOperation?.cancel()
        metadataClient.cancelActiveCommand()
        recentsStore.save([])
        notifyChange()
    }

    func selectScheme(_ scheme: String) {
        guard schemes.contains(scheme), selectedScheme != scheme else { return }
        selectedScheme = scheme
        selectedDestination = nil
        recentDestinationIDs = project.map {
            selectionStore.recentDestinationIDs(for: $0, scheme: scheme)
        } ?? []
        persistSelection()
        refreshRecentSchemeIcons()
        notifyChange()
        refreshDestinations()
    }

    func selectDestination(_ destination: RunDestination) {
        guard destinations.contains(destination), destination.isRunnable else { return }
        selectedDestination = destination
        rememberDestination(destination)
        persistSelection()
        notifyChange()
    }

    func toggleRun() {
        if phase.isActive {
            stop()
        } else {
            run()
        }
    }

    func run() {
        guard let project, let selectedScheme, let selectedDestination, selectedDestination.isRunnable else {
            setPhase(.failed(RunError.noRunnableDestination.localizedDescription))
            return
        }

        launchContext = nil
        setPhase(.building)
        operation?.cancel()
        operation = Task {
            do {
                let context = try await client.buildAndLaunch(
                    project: project,
                    scheme: selectedScheme,
                    destination: selectedDestination
                )
                guard !Task.isCancelled else {
                    try? await client.stop(context)
                    return
                }
                launchContext = context
                setPhase(.running)
            } catch {
                guard !Task.isCancelled else { return }
                setPhase(.failed(error.localizedDescription))
            }
        }
    }

    func handleGlobalRunShortcut() {
        let action = GlobalRunShortcutPolicy.action(
            hasProject: project != nil,
            hasScheme: selectedScheme != nil,
            hasRunnableDestination: selectedDestination?.isRunnable == true
        )
        guard action == .restart else {
            NSSound.beep()
            return
        }

        restartRun()
    }

    private func restartRun() {
        guard let project, let selectedScheme, let selectedDestination else { return }

        let previousOperation = operation
        previousOperation?.cancel()
        client.cancelActiveCommand()
        let previousLaunchContext = launchContext
        launchContext = nil
        setPhase(.building)
        operation = Task {
            do {
                await previousOperation?.value
                guard !Task.isCancelled else { return }
                let context = try await RestartRunSequence.perform(
                    previousContext: previousLaunchContext,
                    stop: { try await client.stop($0) },
                    launch: {
                        try await client.buildAndLaunch(
                            project: project,
                            scheme: selectedScheme,
                            destination: selectedDestination
                        )
                    }
                )
                guard !Task.isCancelled else {
                    try? await client.stop(context)
                    return
                }
                launchContext = context
                setPhase(.running)
            } catch {
                guard !Task.isCancelled else { return }
                setPhase(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        guard phase.isActive else { return }
        setPhase(.stopping)
        operation?.cancel()
        client.cancelActiveCommand()
        let context = launchContext
        launchContext = nil
        operation = Task {
            do {
                try await client.stop(context)
                setPhase(.idle)
            } catch {
                setPhase(.failed(error.localizedDescription))
            }
        }
    }

    private func refreshDestinations() {
        guard let project, let selectedScheme else { return }
        isLoadingDestinations = true
        destinations = []
        notifyChange()
        operation?.cancel()
        client.cancelActiveCommand()
        operation = Task {
            do {
                let updated = try await client.destinations(for: project, scheme: selectedScheme)
                guard !Task.isCancelled, self.project == project, self.selectedScheme == selectedScheme else { return }
                destinations = updated
                let savedID = selectionStore.destinationID(for: project)
                selectedDestination = await client.preferredDestination(
                    in: updated,
                    savedDestinationID: savedID
                )
                isLoadingDestinations = false
                persistSelection()
                notifyChange()
            } catch {
                guard !Task.isCancelled else { return }
                isLoadingDestinations = false
                setPhase(.failed(error.localizedDescription))
            }
        }
    }

    private func addRecent(_ project: XcodeProject) {
        recentProjects.removeAll { $0.id == project.id }
        recentProjects.insert(project, at: 0)
        recentProjects = RecentProjectsPolicy.limited(recentProjects)
        recentsStore.save(recentProjects)
        refreshRecentSchemeIcons()
        notifyChange()
    }

    private func refreshSchemeIcons(
        for project: XcodeProject,
        descriptors: [SchemeDescriptor]
    ) {
        schemeIconOperation?.cancel()
        schemeIconImages = [:]
        schemeIconOperation = Task { [weak self] in
            guard let self else { return }
            for descriptor in descriptors {
                guard !Task.isCancelled, self.project == project else { return }
                if let image = await schemeIconProvider.image(for: descriptor, in: project) {
                    schemeIconImages[descriptor.id] = image
                }
            }
        }
    }

    private func refreshRecentSchemeIcons() {
        recentSchemeIconOperation?.cancel()
        metadataClient.cancelActiveCommand()
        recentSchemeIconImages = [:]
        recentSchemeDescriptors = [:]

        recentSchemeIconOperation = Task { [weak self] in
            guard let self else { return }
            for project in recentProjects {
                guard !Task.isCancelled,
                      recentProjects.contains(where: { $0.id == project.id }) else { return }

                let fileBackedDescriptors = XcodeOutputParser.localSchemeDescriptors(in: project)
                let descriptors: [SchemeDescriptor]
                if let cached = schemeDescriptorsByProject[project.id] {
                    descriptors = cached
                } else if !fileBackedDescriptors.isEmpty {
                    descriptors = fileBackedDescriptors
                    schemeDescriptorsByProject[project.id] = descriptors
                } else if let schemes = try? await metadataClient.schemes(for: project),
                          let inferred = try? await metadataClient.schemeDescriptors(
                            for: project,
                            schemes: schemes,
                            fileBackedDescriptors: []
                          ) {
                    descriptors = inferred
                    schemeDescriptorsByProject[project.id] = descriptors
                } else {
                    descriptors = []
                }

                guard !Task.isCancelled,
                      recentProjects.contains(where: { $0.id == project.id }),
                      let descriptor = RecentSchemePolicy.descriptor(
                        savedScheme: selectionStore.scheme(for: project),
                        availableDescriptors: descriptors
                      ) else { continue }
                recentSchemeDescriptors[project.id] = descriptor
                if let image = await schemeIconProvider.image(for: descriptor, in: project) {
                    recentSchemeIconImages[project.id] = image
                }
                notifyChange()
            }
        }
    }

    private func persistSelection() {
        guard let project else { return }
        selectionStore.save(scheme: selectedScheme, destinationID: selectedDestination?.id, for: project)
    }

    private func rememberDestination(_ destination: RunDestination) {
        guard let project, let selectedScheme else { return }
        recentDestinationIDs = selectionStore.rememberDestination(
            destination.id,
            for: project,
            scheme: selectedScheme
        )
    }

    private func setPhase(_ phase: RunPhase) {
        self.phase = phase
        notifyChange()
    }

    private func notifyChange() {
        onChange?()
    }
}

extension UTType {
    static let xcodeProject = UTType(importedAs: "com.apple.xcode.project", conformingTo: .package)
    static let xcodeWorkspace = UTType(importedAs: "com.apple.dt.document.workspace", conformingTo: .package)
}

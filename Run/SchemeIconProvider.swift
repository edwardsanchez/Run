import AppKit
import Foundation
import QuickLookThumbnailing

enum SchemeIconSource: Equatable, Sendable {
    case iconPackage(URL)
    case imageFile(URL)
}

enum SchemeIconLocator {
    nonisolated static func source(
        for descriptor: SchemeDescriptor,
        in project: XcodeProject,
        fileManager: FileManager = .default
    ) -> SchemeIconSource? {
        guard descriptor.productKind == .app else { return nil }

        let root = project.url.deletingLastPathComponent()
        let names = candidateNames(for: descriptor)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var iconPackages: [URL] = []
        var appIconSets: [URL] = []
        for case let url as URL in enumerator {
            switch url.pathExtension.lowercased() {
            case "icon":
                iconPackages.append(url)
            case "appiconset":
                appIconSets.append(url)
            default:
                continue
            }
        }

        if let iconPackage = bestMatch(in: iconPackages, candidateNames: names) {
            return .iconPackage(iconPackage)
        }

        let genericAppIconSets = appIconSets.filter {
            $0.deletingPathExtension().lastPathComponent == "AppIcon"
        }
        let matchingSet = bestMatch(in: appIconSets, candidateNames: names)
            ?? (genericAppIconSets.count == 1 ? genericAppIconSets[0] : nil)
            ?? (appIconSets.count == 1 ? appIconSets[0] : nil)
        guard let matchingSet,
              let image = appIconImage(in: matchingSet, fileManager: fileManager) else {
            return nil
        }
        return .imageFile(image)
    }

    nonisolated private static func candidateNames(for descriptor: SchemeDescriptor) -> [String] {
        var names = [descriptor.name]
        if let productName = descriptor.productName {
            names.insert(URL(fileURLWithPath: productName).deletingPathExtension().lastPathComponent, at: 0)
        }
        if let appIconName = descriptor.appIconName {
            names.insert(URL(fileURLWithPath: appIconName).deletingPathExtension().lastPathComponent, at: 0)
        }
        return names.map(normalizedName)
    }

    nonisolated private static func bestMatch(in urls: [URL], candidateNames: [String]) -> URL? {
        urls.min { lhs, rhs in
            matchRank(for: lhs, candidateNames: candidateNames)
                < matchRank(for: rhs, candidateNames: candidateNames)
        }.flatMap { url in
            matchRank(for: url, candidateNames: candidateNames) < .max ? url : nil
        }
    }

    nonisolated private static func matchRank(for url: URL, candidateNames: [String]) -> Int {
        let name = normalizedName(url.deletingPathExtension().lastPathComponent)
        return candidateNames.firstIndex(of: name) ?? .max
    }

    nonisolated private static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    nonisolated private static func appIconImage(in appIconSet: URL, fileManager: FileManager) -> URL? {
        let contentsURL = appIconSet.appendingPathComponent("Contents.json")
        guard let data = try? Data(contentsOf: contentsURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let images = root["images"] as? [[String: Any]] else {
            return nil
        }

        let candidates = images.compactMap { entry -> (url: URL, width: Double)? in
            guard entry["appearances"] == nil,
                  let filename = entry["filename"] as? String else { return nil }
            let url = appIconSet.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            let size = (entry["size"] as? String)?
                .split(separator: "x")
                .first
                .flatMap { Double($0) } ?? 0
            let scaleString = (entry["scale"] as? String)?
                .replacingOccurrences(of: "x", with: "")
            let scale = scaleString.flatMap { Double($0) } ?? 1
            return (url, size * scale)
        }

        let targetWidth = 32.0
        let largeEnough = candidates.filter { $0.width >= targetWidth }
        if let closest = largeEnough.min(by: { $0.width < $1.width }) {
            return closest.url
        }
        return candidates.max(by: { $0.width < $1.width })?.url
    }
}

enum RecentSchemePolicy {
    nonisolated static func descriptor(
        savedScheme: String?,
        availableDescriptors: [SchemeDescriptor]
    ) -> SchemeDescriptor? {
        if let savedScheme,
           let saved = availableDescriptors.first(where: { $0.name == savedScheme }) {
            return saved
        }
        if availableDescriptors.count == 1 {
            return availableDescriptors[0]
        }
        return availableDescriptors.first { $0.productKind == .app }
            ?? availableDescriptors.first
    }
}

@MainActor
final class SchemeIconProvider {
    private enum CachedIcon {
        case image(NSImage)
        case unavailable
    }

    private struct Key: Hashable {
        let projectID: String
        let descriptor: SchemeDescriptor
    }

    private var cache: [Key: CachedIcon] = [:]

    func image(for descriptor: SchemeDescriptor, in project: XcodeProject) async -> NSImage? {
        let key = Key(projectID: project.id, descriptor: descriptor)
        if let cached = cache[key] {
            switch cached {
            case .image(let image): return image
            case .unavailable: return nil
            }
        }

        let source = await Task.detached {
            SchemeIconLocator.source(for: descriptor, in: project)
        }.value

        let image: NSImage?
        switch source {
        case .iconPackage(let url):
            image = await thumbnail(for: url)
        case .imageFile(let url):
            image = NSImage(contentsOf: url)
        case nil:
            image = nil
        }

        cache[key] = image.map(CachedIcon.image) ?? .unavailable
        return image
    }

    private func thumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 64, height: 64),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }
}

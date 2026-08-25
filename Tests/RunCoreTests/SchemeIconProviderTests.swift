import AppKit
import Foundation
import Testing
@testable import RunCore

struct SchemeIconProviderTests {
    @Test @MainActor func enrichedMetadataDoesNotReuseAnUnavailableCacheEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectURL = root.appendingPathComponent("Monogram.xcodeproj")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        for name in ["AppIconDev", "AppIconRelease"] {
            let iconSet = root.appendingPathComponent("Assets.xcassets/\(name).appiconset")
            try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
            let contents = """
            {"images":[{"filename":"Icon.png","size":"32x32","scale":"1x"}]}
            """
            try Data(contents.utf8).write(to: iconSet.appendingPathComponent("Contents.json"))
            let imageData = try #require(Data(base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLJAAAAAElFTkSuQmCC"
            ))
            try imageData.write(to: iconSet.appendingPathComponent("Icon.png"))
        }

        let project = try #require(XcodeProject(url: projectURL))
        let provider = SchemeIconProvider()
        let unresolved = SchemeDescriptor(
            name: "MonogramDev",
            productName: "MonogramDev.app",
            productKind: .app
        )
        #expect(await provider.image(for: unresolved, in: project) == nil)

        let enriched = SchemeDescriptor(
            name: "MonogramDev",
            productName: "MonogramDev.app",
            productKind: .app,
            appIconName: "AppIconDev"
        )
        #expect(await provider.image(for: enriched, in: project) != nil)
    }

    @Test func configuredAppIconNamesSelectTheCorrectVariantPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectURL = root.appendingPathComponent("Monogram.xcodeproj")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let mappings = [
            ("MonogramDev", "MonogramDev.app", "AppIconDev"),
            ("MonogramPrivateBeta", "Monogram.app", "AppIconAlpha"),
            ("MonogramRelease", "Monogram.app", "AppIcon"),
            ("MonogramTestFlight", "Monogram.app", "AppIconInternal"),
        ]
        for appIconName in mappings.map(\.2) {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Resources/\(appIconName).icon"),
                withIntermediateDirectories: true
            )
        }
        let project = try #require(XcodeProject(url: projectURL))

        for (scheme, product, appIconName) in mappings {
            let descriptor = SchemeDescriptor(
                name: scheme,
                productName: product,
                productKind: .app,
                appIconName: appIconName
            )
            let source = try #require(SchemeIconLocator.source(for: descriptor, in: project))
            guard case .iconPackage(let locatedURL) = source else {
                Issue.record("Expected \(appIconName).icon for \(scheme)")
                continue
            }
            let expectedURL = root.appendingPathComponent("Resources/\(appIconName).icon")
            #expect(locatedURL.resolvingSymlinksInPath() == expectedURL.resolvingSymlinksInPath())
        }
    }

    @Test func generatedAppSchemeLocatesItsIconComposerPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectURL = root.appendingPathComponent("Setts.xcodeproj")
        let iconURL = root.appendingPathComponent("Setts/Setts.icon")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconURL, withIntermediateDirectories: true)
        let buildSettings = Data(#"[{"target":"Setts","buildSettings":{"FULL_PRODUCT_NAME":"Setts.app","WRAPPER_EXTENSION":"app"}}]"#.utf8)

        let project = try #require(XcodeProject(url: projectURL))
        let descriptor = try XcodeOutputParser.schemeDescriptor(
            name: "Setts",
            fromBuildSettings: buildSettings
        )

        let source = try #require(SchemeIconLocator.source(for: descriptor, in: project))
        guard case .iconPackage(let locatedURL) = source else {
            Issue.record("Expected an Icon Composer package")
            return
        }
        #expect(locatedURL.resolvingSymlinksInPath() == iconURL.resolvingSymlinksInPath())
    }

    @Test func findsIconComposerPackageMatchingTheRunnableProduct() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectURL = root.appendingPathComponent("Demo.xcodeproj")
        let iconURL = root.appendingPathComponent("Sources/Demo.icon")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconURL, withIntermediateDirectories: true)

        let project = try #require(XcodeProject(url: projectURL))
        let descriptor = SchemeDescriptor(name: "Demo Scheme", productName: "Demo.app", productKind: .app)

        let source = try #require(SchemeIconLocator.source(for: descriptor, in: project))
        guard case .iconPackage(let locatedURL) = source else {
            Issue.record("Expected an Icon Composer package")
            return
        }
        #expect(locatedURL.resolvingSymlinksInPath() == iconURL.resolvingSymlinksInPath())
    }

    @Test func choosesClosestClassicAppIconAtOrAboveThirtyTwoPixels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectURL = root.appendingPathComponent("Demo.xcodeproj")
        let iconSetURL = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

        let contents = """
        {
          "images": [
            { "filename": "Demo16.png", "idiom": "mac", "size": "16x16", "scale": "1x" },
            { "filename": "Demo32.png", "idiom": "mac", "size": "16x16", "scale": "2x" },
            { "filename": "Demo128.png", "idiom": "mac", "size": "128x128", "scale": "1x" }
          ],
          "info": { "author": "xcode", "version": 1 }
        }
        """
        try Data(contents.utf8).write(to: iconSetURL.appendingPathComponent("Contents.json"))
        for name in ["Demo16.png", "Demo32.png", "Demo128.png"] {
            try Data([0]).write(to: iconSetURL.appendingPathComponent(name))
        }

        let project = try #require(XcodeProject(url: projectURL))
        let descriptor = SchemeDescriptor(name: "Demo", productName: "Demo.app", productKind: .app)

        let source = try #require(SchemeIconLocator.source(for: descriptor, in: project))
        guard case .imageFile(let locatedURL) = source else {
            Issue.record("Expected a classic app-icon image")
            return
        }
        let expectedURL = iconSetURL.appendingPathComponent("Demo32.png")
        #expect(locatedURL.resolvingSymlinksInPath() == expectedURL.resolvingSymlinksInPath())
    }

    @Test func appWithoutIconUsesFallbackWhileOtherProductKindsKeepTheirSymbols() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectURL = root.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let project = try #require(XcodeProject(url: projectURL))
        let app = SchemeDescriptor(name: "Demo", productName: "Demo.app", productKind: .app)
        let framework = SchemeDescriptor(
            name: "DemoKit",
            productName: "DemoKit.framework",
            productKind: .framework
        )

        #expect(SchemeIconLocator.source(for: app, in: project) == nil)
        #expect(app.usesAppIconFallback)
        #expect(!framework.usesAppIconFallback)
        #expect(framework.symbolName == "shippingbox")
    }

    @Test func ambiguousGenericAppIconSetsFallBackInsteadOfShowingAnotherTargetsIcon() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectURL = root.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        for folder in ["First", "Second"] {
            let set = root.appendingPathComponent("\(folder).xcassets/AppIcon.appiconset")
            try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
            let contents = """
            { "images": [{ "filename": "Icon.png", "size": "32x32", "scale": "1x" }] }
            """
            try Data(contents.utf8).write(to: set.appendingPathComponent("Contents.json"))
            try Data([0]).write(to: set.appendingPathComponent("Icon.png"))
        }

        let project = try #require(XcodeProject(url: projectURL))
        let descriptor = SchemeDescriptor(name: "Demo", productName: "Demo.app", productKind: .app)

        #expect(SchemeIconLocator.source(for: descriptor, in: project) == nil)
    }

    @Test func recentsPreferTheSavedSchemeAndOtherwisePreferAnApp() {
        let app = SchemeDescriptor(name: "Demo", productName: "Demo.app", productKind: .app)
        let tests = SchemeDescriptor(name: "DemoTests", productName: "DemoTests.xctest", productKind: .test)

        #expect(
            RecentSchemePolicy.descriptor(
                savedScheme: "DemoTests",
                availableDescriptors: [app, tests]
            ) == tests
        )
        #expect(
            RecentSchemePolicy.descriptor(
                savedScheme: nil,
                availableDescriptors: [tests, app]
            ) == app
        )
    }
}

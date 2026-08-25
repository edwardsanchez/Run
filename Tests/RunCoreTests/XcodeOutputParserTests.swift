import Foundation
import Testing
@testable import RunCore

struct XcodeOutputParserTests {
    @Test func parsesProjectSchemes() throws {
        let data = Data(#"{"project":{"schemes":["Second","First"]}}"#.utf8)
        #expect(try XcodeOutputParser.schemes(from: data) == ["Second", "First"])
    }

    @Test func infersGeneratedAppSchemeFromBuildSettings() throws {
        let data = Data(#"[{"target":"Setts","buildSettings":{"TARGET_NAME":"Setts","FULL_PRODUCT_NAME":"Setts.app","WRAPPER_EXTENSION":"app"}}]"#.utf8)

        let descriptor = try XcodeOutputParser.schemeDescriptor(
            name: "Setts",
            fromBuildSettings: data
        )

        #expect(descriptor == SchemeDescriptor(name: "Setts", productName: "Setts.app", productKind: .app))
        #expect(descriptor.usesAppIconFallback)
    }

    @Test func generatedSchemePrefersItsMatchingTargetBuildSettings() throws {
        let data = Data(#"[{"target":"SettsTests","buildSettings":{"FULL_PRODUCT_NAME":"SettsTests.xctest","WRAPPER_EXTENSION":"xctest"}},{"target":"Setts","buildSettings":{"FULL_PRODUCT_NAME":"Setts.app","WRAPPER_EXTENSION":"app"}}]"#.utf8)

        let descriptor = try XcodeOutputParser.schemeDescriptor(
            name: "Setts",
            fromBuildSettings: data
        )

        #expect(descriptor.productName == "Setts.app")
        #expect(descriptor.productKind == .app)
    }

    @Test func enrichesFileBackedSchemesWithTheirConfiguredAppIconNames() throws {
        let mappings = [
            ("MonogramDev", "MonogramDev.app", "AppIconDev"),
            ("MonogramPrivateBeta", "Monogram.app", "AppIconAlpha"),
            ("MonogramRelease", "Monogram.app", "AppIcon"),
            ("MonogramTestFlight", "Monogram.app", "AppIconInternal"),
        ]

        for (scheme, product, appIconName) in mappings {
            let fallback = SchemeDescriptor(name: scheme, productName: product, productKind: .app)
            let data = Data("""
            [{"target":"Target","buildSettings":{
              "FULL_PRODUCT_NAME":"\(product)",
              "WRAPPER_EXTENSION":"app",
              "ASSETCATALOG_COMPILER_APPICON_NAME":"\(appIconName)"
            }}]
            """.utf8)

            let descriptor = try XcodeOutputParser.schemeDescriptor(
                name: scheme,
                fallback: fallback,
                fromBuildSettings: data
            )

            #expect(descriptor.productName == product)
            #expect(descriptor.productKind == .app)
            #expect(descriptor.appIconName == appIconName)
        }
    }

    @Test func parsesConcreteAndGenericDestinations() {
        let output = """
        Destinations compatible with the "Demo" scheme:
            { platform:macOS, arch:arm64, id:MAC-ID, name:My Mac }
            { platform:macOS, arch:arm64, variant:Mac Catalyst, id:CATALYST-ID, name:My Mac }
            { platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:IOS-ON-MAC-ID, name:My Mac }
            { platform:iOS Simulator, id:SIM-ID, OS:27.0, name:iPhone 18 Pro }
            { platform:iOS Simulator, name:Any iOS Simulator Device }
        """

        let destinations = XcodeOutputParser.destinations(from: output)
        #expect(destinations.count == 4)
        #expect(destinations[0].isMac)
        #expect(destinations[1].isMac)
        #expect(destinations[1].id.contains("CATALYST-ID"))
        #expect(destinations.contains { $0.id.contains("IOS-ON-MAC-ID") } == false)
        #expect(destinations[2].isSimulator)
        #expect(destinations[3].isGeneric)
        #expect(!destinations[3].isRunnable)
    }

    @Test func bootedSimulatorIsPreferredOverListOrder() {
        let mac = RunDestination(platform: "macOS", name: "My Mac", identifier: "MAC", isGeneric: false)
        let simulator = RunDestination(platform: "iOS Simulator", name: "iPhone", identifier: "SIM", isGeneric: false)
        #expect(XcodeOutputParser.preferredDestination([mac, simulator], bootedSimulatorIDs: ["SIM"]) == simulator)
    }

    @Test func parsesLaunchableAppBuildSettings() throws {
        let data = Data(#"[{"buildSettings":{"WRAPPER_EXTENSION":"framework"}},{"buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp/Build","FULL_PRODUCT_NAME":"Demo.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.demo","EXECUTABLE_NAME":"Demo"}}]"#.utf8)
        let settings = try XcodeOutputParser.appBuildSettings(from: data)
        #expect(settings.path.path == "/tmp/Build/Demo.app")
        #expect(settings.bundleIdentifier == "com.example.demo")
        #expect(settings.executableName == "Demo")
    }

    @Test func usesXcodeSchemeOrderAsTheInitialScheme() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectURL = root.appendingPathComponent("Demo.xcodeproj")
        let schemesURL = projectURL.appendingPathComponent("xcuserdata/test.xcuserdatad/xcschemes")
        try FileManager.default.createDirectory(at: schemesURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let propertyList: [String: Any] = [
            "SchemeUserState": [
                "Second.xcscheme_^#shared#^_": ["orderHint": 5],
                "First.xcscheme_^#shared#^_": ["orderHint": 0],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        try data.write(to: schemesURL.appendingPathComponent("xcschememanagement.plist"))
        let project = try #require(XcodeProject(url: projectURL))

        #expect(XcodeOutputParser.preferredScheme(in: project, availableSchemes: ["Second", "First"]) == "First")
    }

    @Test func findsPhysicalDeviceProcessIdentifierInDevicectlOutput() {
        let data = Data(#"{"result":{"deviceIdentifier":"DEVICE","process":{"processIdentifier":8675}}}"#.utf8)
        #expect(XcodeOutputParser.deviceProcessIdentifier(from: data) == 8675)
    }

    @Test func discoversAFileBackedSchemeImmediately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectURL = root.appendingPathComponent("Demo.xcodeproj")
        let schemesURL = projectURL.appendingPathComponent("xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: schemesURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schemeXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme version="1.7">
          <BuildAction>
            <BuildableReference BuildableName="Demo.app" BlueprintName="Demo"></BuildableReference>
          </BuildAction>
        </Scheme>
        """
        try Data(schemeXML.utf8).write(to: schemesURL.appendingPathComponent("Demo.xcscheme"))
        let project = try #require(XcodeProject(url: projectURL))

        #expect(XcodeOutputParser.localSchemes(in: project) == ["Demo"])
        let descriptor = try #require(XcodeOutputParser.localSchemeDescriptors(in: project).first)
        #expect(descriptor.productName == "Demo.app")
        #expect(descriptor.productKind == .app)
        #expect(descriptor.symbolName == "app")
        #expect(descriptor.usesAppIconFallback)
        #expect(XcodeOutputParser.preferredScheme(in: project, availableSchemes: ["Demo"]) == "Demo")
    }

    @Test func filtersPackageSchemesWhenProjectSchemesAreKnown() {
        let discovered = ["ChatKit", "ChatKitModels", "Rio", "Rio Scroll Test"]
        let local = ["Rio", "Rio Scroll Test"]

        #expect(XcodeOutputParser.userSchemes(discovered: discovered, local: local) == local)
        #expect(XcodeOutputParser.userSchemes(discovered: discovered, local: []) == discovered)
    }

    @Test func groupsOnlyRunnableDestinationsWithRecentsFirst() {
        let destinations = [
            RunDestination(platform: "iOS Simulator", name: "iPhone 17", identifier: "SIM", isGeneric: false, osVersion: "27.0"),
            RunDestination(platform: "iOS", name: "Lorax", identifier: "PHONE", isGeneric: false),
            RunDestination(platform: "macOS", name: "My Mac", identifier: "MAC", isGeneric: false),
            RunDestination(platform: "iOS", name: "Unavailable", identifier: "OLD", isGeneric: false, availabilityError: "Unsupported"),
            RunDestination(platform: "iOS", name: "Any iOS Device", identifier: nil, isGeneric: true),
        ]

        let groups = XcodeOutputParser.runningDestinationGroups(
            from: destinations,
            recentDestinationIDs: [destinations[1].id]
        )
        #expect(groups.map(\.name) == ["Recent", "Devices", "Simulators"])
        #expect(groups[0].destinations.map(\.id) == [destinations[1].id])
        #expect(groups[1].destinations.map(\.id) == [destinations[2].id])
        #expect(groups[2].destinations.first?.osVersion == "27.0")
        #expect(groups.flatMap(\.destinations).contains { $0.isGeneric } == false)
        #expect(groups.flatMap(\.destinations).contains { $0.availabilityError != nil } == false)
    }

    @Test func destinationIdentityDistinguishesCompatibleAndIncompatibleVariants() {
        let available = RunDestination(
            platform: "macOS",
            name: "My Mac",
            identifier: "MAC",
            isGeneric: false
        )
        let incompatible = RunDestination(
            platform: "iOS",
            name: "My Mac",
            identifier: "MAC",
            isGeneric: false,
            availabilityError: "Unsupported"
        )

        #expect(available.id != incompatible.id)
    }
}

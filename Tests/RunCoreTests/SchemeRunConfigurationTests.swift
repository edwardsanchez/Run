import Foundation
import Testing
@testable import RunCore

struct SchemeRunConfigurationTests {
    @Test func parsesTheSelectedRunAction() throws {
        let fixture = try SchemeFixture(name: "Demo", xml: """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme version="1.7">
          <LaunchAction
            buildConfiguration="Staging"
            useCustomWorkingDirectory="YES"
            customWorkingDirectory="$(SRCROOT)/Working Folder"
            enableAddressSanitizer="YES"
            enableThreadSanitizer="YES"
            enableUBSanitizer="YES">
            <PreActions>
              <ExecutionAction>
                <ActionContent title="Prepare &amp; seed" scriptText="echo &quot;$CONFIGURATION&quot;&#10;touch marker">
                  <EnvironmentBuildable>
                    <BuildableReference BlueprintName="Demo Tools" />
                  </EnvironmentBuildable>
                </ActionContent>
              </ExecutionAction>
            </PreActions>
            <BuildableProductRunnable>
              <BuildableReference BuildableName="Demo.app" BlueprintName="Demo App" />
            </BuildableProductRunnable>
            <CommandLineArguments>
              <CommandLineArgument argument="--message &quot;hello world&quot;" isEnabled="YES" />
              <CommandLineArgument argument="--disabled" isEnabled="NO" />
            </CommandLineArguments>
            <EnvironmentVariables>
              <EnvironmentVariable key="API_BASE" value="$(SERVICE_ROOT)/v1?a=1&amp;b=2" isEnabled="YES" />
              <EnvironmentVariable key="IGNORED" value="secret" isEnabled="NO" />
            </EnvironmentVariables>
            <PostActions>
              <ExecutionAction>
                <ActionContent title="Clean up" scriptText="rm -f marker" />
              </ExecutionAction>
            </PostActions>
          </LaunchAction>
        </Scheme>
        """)
        defer { fixture.remove() }

        let configuration = try SchemeRunConfigurationParser.configuration(
            in: fixture.project,
            scheme: "Demo"
        )

        #expect(configuration.buildConfiguration == "Staging")
        #expect(configuration.runnableKind == .buildableProduct)
        #expect(configuration.launchStyle == "0")
        #expect(configuration.executableTargetName == "Demo App")
        #expect(configuration.executableProductName == "Demo.app")
        #expect(configuration.argumentEntries == ["--message \"hello world\""])
        #expect(configuration.environment == ["API_BASE": "$(SERVICE_ROOT)/v1?a=1&b=2"])
        #expect(configuration.workingDirectory == "$(SRCROOT)/Working Folder")
        #expect(configuration.preActions == [SchemeExecutionAction(
            title: "Prepare & seed",
            script: "echo \"$CONFIGURATION\"\ntouch marker",
            targetName: "Demo Tools"
        )])
        #expect(configuration.postActions.first?.title == "Clean up")
        #expect(configuration.enablesAddressSanitizer)
        #expect(configuration.enablesThreadSanitizer)
        #expect(configuration.enablesUndefinedBehaviorSanitizer)
    }

    @Test func resolvesMacrosArgumentsAndWorkingDirectory() {
        let configuration = SchemeRunConfiguration(
            runnableKind: .buildableProduct,
            launchStyle: "0",
            buildConfiguration: "Dev",
            executableTargetName: "Demo",
            executableProductName: "Demo.app",
            argumentEntries: ["--flag", "--message 'hello world'", "--path $(SRCROOT)/A\\ B", "\"\""],
            environment: ["ENDPOINT": "$(ROOT_URL)/v1", "UNRESOLVED": "$(MISSING)"],
            workingDirectory: "$(SRCROOT)/Fixtures",
            preActions: [],
            postActions: [],
            enablesAddressSanitizer: true,
            enablesThreadSanitizer: false,
            enablesUndefinedBehaviorSanitizer: true
        )

        let resolved = SchemeLaunchPlan.resolve(
            configuration,
            buildSettings: ["SRCROOT": "/tmp/Demo", "ROOT_URL": "https://example.test"],
            inheritedEnvironment: [:]
        )

        #expect(resolved.arguments == ["--flag", "--message", "hello world", "--path", "/tmp/Demo/A B", ""])
        #expect(resolved.environment == [
            "ENDPOINT": "https://example.test/v1",
            "UNRESOLVED": "$(MISSING)",
        ])
        #expect(resolved.workingDirectory?.path == "/tmp/Demo/Fixtures")
        #expect(SchemeLaunchPlan.sanitizerArguments(for: configuration) == [
            "-enableAddressSanitizer", "YES",
            "-enableUndefinedBehaviorSanitizer", "YES",
        ])
    }

    @Test func buildsDestinationSpecificLaunchCommandsWithoutPuttingEnvironmentInArguments() {
        let configuration = ResolvedSchemeRunConfiguration(
            buildConfiguration: "Debug",
            arguments: ["--preview", "Sample Name"],
            environment: ["TOKEN": "private", "MODE": "preview"],
            workingDirectory: URL(fileURLWithPath: "/tmp/Working"),
            preActions: [],
            postActions: [],
            enablesAddressSanitizer: false,
            enablesThreadSanitizer: false,
            enablesUndefinedBehaviorSanitizer: false
        )

        #expect(SchemeLaunchPlan.simulatorLaunchArguments(
            identifier: "SIM",
            bundleIdentifier: "com.example.demo",
            configuration: configuration
        ) == [
            "launch", "--terminate-running-process", "SIM", "com.example.demo", "--preview", "Sample Name",
        ])
        #expect(SchemeLaunchPlan.simulatorEnvironment(for: configuration) == [
            "SIMCTL_CHILD_TOKEN": "private", "SIMCTL_CHILD_MODE": "preview",
        ])

        let deviceArguments = SchemeLaunchPlan.deviceLaunchArguments(
            identifier: "PHONE",
            bundleIdentifier: "com.example.demo",
            configuration: configuration
        )
        #expect(deviceArguments == [
            "device", "process", "launch", "--device", "PHONE",
            "--terminate-existing", "--json-output", "-",
            "--working-directory", "/tmp/Working",
            "com.example.demo", "--preview", "Sample Name",
        ])
        #expect(!deviceArguments.contains("private"))
        #expect(SchemeLaunchPlan.deviceEnvironment(for: configuration) == [
            "DEVICECTL_CHILD_TOKEN": "private", "DEVICECTL_CHILD_MODE": "preview",
        ])
    }

    @Test func selectsTheSchemeRunnableInsteadOfTheFirstAppProduct() throws {
        let data = Data("""
        [
          {"target":"Helper","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp","FULL_PRODUCT_NAME":"Helper.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.helper","EXECUTABLE_NAME":"Helper","TARGET_NAME":"Helper"}},
          {"target":"Demo App","buildSettings":{"WRAPPER_EXTENSION":"app","TARGET_BUILD_DIR":"/tmp","FULL_PRODUCT_NAME":"Demo.app","PRODUCT_BUNDLE_IDENTIFIER":"com.example.demo","EXECUTABLE_NAME":"Demo","TARGET_NAME":"Demo App"}}
        ]
        """.utf8)

        let settings = try XcodeOutputParser.appBuildSettings(
            from: data,
            targetName: "Demo App",
            productName: "Demo.app"
        )

        #expect(settings.bundleIdentifier == "com.example.demo")
        #expect(settings.path.path == "/tmp/Demo.app")
        #expect(throws: RunError.appProductNotFound) {
            try XcodeOutputParser.appBuildSettings(from: data, targetName: "Missing")
        }
    }

    @Test func fallsBackForSchemesGeneratedByXcodeWithoutAFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectURL = root.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try #require(XcodeProject(url: projectURL))

        #expect(try SchemeRunConfigurationParser.configuration(in: project, scheme: "Generated") == .fallback)
    }

    @Test func findsAProjectSchemeSelectedThroughAWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspaceURL = root.appendingPathComponent("Demo.xcworkspace")
        let projectURL = root.appendingPathComponent("App/Demo.xcodeproj")
        let schemesURL = projectURL.appendingPathComponent("xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: schemesURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("""
        <Workspace version="1.0"><FileRef location="group:App/Demo.xcodeproj" /></Workspace>
        """.utf8).write(to: workspaceURL.appendingPathComponent("contents.xcworkspacedata"))
        try Data("""
        <Scheme version="1.7">
          <LaunchAction buildConfiguration="Workspace Debug">
            <BuildableProductRunnable>
              <BuildableReference BuildableName="Demo.app" BlueprintName="Demo" />
            </BuildableProductRunnable>
          </LaunchAction>
        </Scheme>
        """.utf8).write(to: schemesURL.appendingPathComponent("Demo.xcscheme"))
        let workspace = try #require(XcodeProject(url: workspaceURL))

        let configuration = try SchemeRunConfigurationParser.configuration(in: workspace, scheme: "Demo")

        #expect(configuration.buildConfiguration == "Workspace Debug")
        #expect(configuration.executableTargetName == "Demo")
    }

    @Test func identifiesRunActionsThatCannotBeFaithfullyLaunched() throws {
        let fixture = try SchemeFixture(name: "External", xml: """
        <Scheme version="1.7">
          <LaunchAction buildConfiguration="Debug" launchStyle="1">
            <PathRunnable FilePath="/usr/bin/example" />
          </LaunchAction>
        </Scheme>
        """)
        defer { fixture.remove() }

        let configuration = try SchemeRunConfigurationParser.configuration(
            in: fixture.project,
            scheme: "External"
        )

        #expect(configuration.runnableKind == .unsupported("PathRunnable"))
        #expect(configuration.launchStyle == "1")
    }
}

private struct SchemeFixture {
    let root: URL
    let project: XcodeProject

    init(name: String, xml: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectURL = root.appendingPathComponent("Demo.xcodeproj")
        let schemesURL = projectURL.appendingPathComponent("xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: schemesURL, withIntermediateDirectories: true)
        try Data(xml.utf8).write(to: schemesURL.appendingPathComponent(name + ".xcscheme"))
        project = try #require(XcodeProject(url: projectURL))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

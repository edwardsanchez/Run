# Run

Run is a small macOS menu bar app for building and launching Xcode app schemes without keeping Xcode open.

## Using Run

1. Launch Run.
2. Click **Run** in the menu bar and choose **Open…**.
3. Select an `.xcodeproj` or `.xcworkspace`.
4. Choose a scheme and run destination from the menu.
5. Click the play icon in the menu bar.

## How it works

Run reads the schemes and destinations reported by the selected Xcode installation. It uses `xcodebuild` to build the scheme, then launches the resulting app with the appropriate system tool:

- macOS apps are launched through AppKit.
- Simulator destinations are booted and stopped with `simctl`, while apps are installed and launched with `devicectl`.
- Apps on physical devices are also installed and launched with `devicectl`.

For ordinary app schemes, Run honors the Run action's build configuration, enabled command-line arguments and environment variables, custom working directory, pre-actions, post-actions, and Address, Thread, and Undefined Behavior Sanitizer settings.

## Requirements

- macOS 26 or later.
- Xcode 27 or later. Run uses `DEVELOPER_DIR` when it is set, otherwise it looks for Xcode in `/Applications`.
- Any signing, pairing, Developer Mode, and device trust setup required by the project must already be configured.

## Known limitations

Run reproduces the common build-install-launch path with public command-line tools. It does not host Xcode's debugger or fully reproduce every behavior of Xcode's Run action.

- Only schemes that build an app product can be launched. Test, framework, library, command-line tool, extension-only, and other non-app schemes are not supported.
- Schemes that run a custom executable (`PathRunnable`), use a remote runnable (`RemoteRunnable`), or wait for an executable to be launched are rejected.
- Breakpoints, debugger attachment and console integration, view debugging, memory graph debugging, GPU or frame capture, profiling, and other Xcode-owned diagnostics are unavailable.
- Test, Profile, Analyze, and Archive scheme actions are not run.
- My Mac destinations for apps designed for iPad or iPhone are hidden because their launch pipeline is only available through Xcode.
- Scheme options beyond the explicitly supported settings listed above may be ignored or rejected. Xcode can add new scheme behaviors that Run does not yet understand.
- Device launches still depend on Xcode's command-line device support and the project's signing configuration. A destination that appears in the menu may remain unavailable until Xcode's setup requirements are satisfied.

When Run cannot identify a launchable app or cannot faithfully handle a scheme's Run action, it reports an error instead of launching a different product.

## License

Run is available under the [MIT License](LICENSE).

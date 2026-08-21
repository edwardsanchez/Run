# AGENTS.md

## Project

Run is a small macOS menu bar app that builds and launches Xcode app schemes without requiring Xcode to remain open. It discovers schemes and destinations, builds with `xcodebuild`, and launches macOS, Simulator, or device apps through the appropriate public system tool.

Keep Run menu-bar-only. Treat `Run.xcodeproj` as the app project and `Package.swift` as the testable `RunCore` package boundary. The app currently stores recents and selections in `UserDefaults`; it does not currently use SwiftData.

## Architecture

- Keep Xcode command execution, scheme parsing, launch planning, persistence, and state transitions outside SwiftUI presentation code.
- Keep shared app state in `@MainActor @Observable` types. Use Observation (`@Observable`, `@State`, `@Bindable`, and environment values) instead of introducing `ObservableObject` or `@Published`.
- Keep AppKit interop narrow and purposeful. `StatusItemController` owns the native status item and popover boundary; SwiftUI should own declarative menu content where practical.
- Preserve Run's fail-safe behavior: reject unsupported schemes or launch behavior instead of silently launching a different product.
- Do not add third-party dependencies without asking first.

## Swift and SwiftUI

- Use modern Swift concurrency. Do not introduce `DispatchQueue.main.async` when actor isolation or `Task` expresses the work.
- Prefer Swift-native and modern Foundation APIs, avoid force unwraps and force `try`, and keep builds warning-free.
- Use `foregroundStyle()` instead of `foregroundColor()`, `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`, modern `onChange` overloads, and `Task.sleep(for:)` instead of nanosecond sleeps.
- Use `Button` for ordinary actions rather than `onTapGesture`. Use `localizedStandardContains()` for user-facing filtering.
- Keep views small by extracting dedicated `View` types rather than computed `some View` properties. Add previews for new SwiftUI views when the view can be previewed meaningfully.
- Do not hard-code layout or styling values unless the design requires them. When native menu behavior requires AppKit-specific measurements, centralize them rather than scattering literals.
- Use `Logger` rather than `print` for durable diagnostics.

## SwiftData

If SwiftData is introduced, keep persistence behind a small interface so app behavior remains testable without the user's real store.

- Keep `ModelContext` work on the correct actor and do not pass live model objects across isolation boundaries.
- Give each test a fresh in-memory `ModelContainer`; never read from or write to the user's application store.
- Test persistence behavior through public operations: saving, fetching, ordering, deletion, relationships, migration-relevant defaults, and failure handling.
- Do not test SwiftData internals, generated schema details, or the exact implementation shape of models unless that shape is itself a compatibility contract.

## Testing policy

Tests must prove behavior and user-visible outcomes, not restate the implementation.

- Do not add README or documentation-content tests. Documentation is not an executable product contract, and tests must not pin phrases or headings.
- UI and presentation tests may verify actions, accessibility reachability, selection and navigation behavior, state transitions, persistence, commands sent to collaborators, and resulting side effects.
- Do not assert UI copy, labels, formatted strings, modifiers, colors, materials, fonts, opacity, spacing, frames, coordinates, corner radii, animation constants, row heights, icon names, or other presentation values.
- Do not expose private layout constants or source-shaped helper APIs solely so a test can compare them to expected values.
- Exact values are appropriate only when they are part of an externally meaningful behavioral contract, such as parsed scheme settings, launch arguments, destination selection, persisted ordering, or a surfaced error.
- Prefer testing through a public seam with fakes or temporary fixtures. A test should answer whether Run performed the requested work, not whether the code was written in a particular way.
- Use manual or purpose-built visual verification for appearance changes. Do not replace behavioral tests with screenshots, and do not treat a passing build as visual proof.

When touching existing noisy tests such as README-content checks or menu-layout constant checks, remove or replace them with behavior-focused coverage rather than extending them.

## Verification

- Run focused Swift package tests with a full Xcode toolchain:

  ```bash
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
  ```

- Build the app after app-target changes:

  ```bash
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Run.xcodeproj -scheme Run -configuration Debug build
  ```

- For menu appearance or interaction changes, also launch the app and verify the affected behavior live. Report automated test/build results separately from visual verification.
- For documentation-only changes, use `git diff --check -- AGENTS.md` and inspect the narrowed diff; do not run unrelated app builds.

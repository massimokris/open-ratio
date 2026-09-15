# Open Ratio — Agent Instructions

Project instructions for coding agents. Keep shared guidance in this file so agent-specific entry files can refer to it.

## Overview

Open Ratio is a local macOS menu bar app for noticing the balance between **Create** and **Consume**. It tracks time in the active app and optionally in websites, then shows daily ratios and history. Activity and preferences stay on the Mac. The app uses SwiftUI and AppKit with system frameworks only.

The product is a compact menu bar panel: 360 × 352 points of content plus an 8-point anchor. Tracking, history and settings share that panel. Keep its existing layout and interactions consistent when making changes.

## Architecture

| Area | Implementation |
|------|----------------|
| App shell | `LSUIElement=true`, an AppKit `NSStatusItem` and one main borderless `NSPanel`; no Dock icon. |
| UI | SwiftUI views hosted by `NSHostingController` inside the panel. |
| State | `@MainActor AppModel: ObservableObject` coordinates observations, actions, persistence and presentation. |
| Domain | `RatioCore` handles time accounting, categories, ratios, history and hostname normalization independently of AppKit and SwiftUI. |
| App tracking | `NSWorkspace` reports foreground apps; CoreGraphics supplies idle duration. |
| Website tracking | Apple Events read the active tab in the supported default browser after optional Automation consent. |
| Storage | Versioned JSON with atomic writes and a previous valid backup in `~/Library/Application Support/RatioNative/`; preferences use `UserDefaults`. |
| Distribution | Swift Package Manager builds the executable. Native scripts assemble a universal app and a DMG with a saved Finder layout. |

### Key architecture decisions

- **Accounting:** Unclassified time counts toward tracked totals but is excluded from the ratio. Changing a category recalculates ratios, including history, without changing measured time. Preserve recorded local days and the handling of midnight, idle time, sleep and clock changes.
- **Demo and reset:** Demo uses a separate in-memory ledger. Reset clears today’s tracked time in the current mode; a real-day reset can be undone during the current launch. Keep demo actions separate from real history.
- **Browser access:** One Track websites setting follows the system default browser. Other browsers and unavailable website capture use app-level tracking. Only normalized HTTP(S) hostnames cross into the domain. Browser launch and consent requests belong to explicit enable/connect/retry actions; background sampling does not open browsers or prompt.
- **Stable identity:** The public name is Open Ratio. The executable and Swift package remain `RatioNative`, the bundle identifier is `com.rationative.RatioNative`, and the data directory remains `RatioNative`. Preserve these identities when changing display text so existing data and preferences remain available.

## Key files

Paths are relative to the repository root.

| File or directory | Purpose |
|-------------------|---------|
| [RatioNativeApp.swift](Sources/RatioNative/RatioNativeApp.swift) | App entry point, menu bar item, panel lifecycle, commands and dismissal. |
| [AppModel.swift](Sources/RatioNative/AppModel.swift) | Shared app state, observations, actions and save coordination. |
| [AppModel+History.swift](Sources/RatioNative/AppModel+History.swift) | History presentation and CSV export actions. |
| [MenuBarView.swift](Sources/RatioNative/MenuBarView.swift) | Panel layout, status headers, navigation and footer. |
| [TodayView.swift](Sources/RatioNative/TodayView.swift), [HistoryView.swift](Sources/RatioNative/HistoryView.swift), [PreferencesView.swift](Sources/RatioNative/PreferencesView.swift) | Tracking rows, daily history and inline settings. |
| [ForegroundActivityMonitor.swift](Sources/RatioNative/ForegroundActivityMonitor.swift) | Foreground app, idle, sleep and session observations; app exclusions. |
| [BrowserTrackingCoordinator.swift](Sources/RatioNative/BrowserTrackingCoordinator.swift) | Default-browser selection, optional website capture and stale-result handling. |
| [NativeBrowserAccess.swift](Sources/RatioNative/NativeBrowserAccess.swift) | Explicit browser opening and native Automation permission requests. |
| [Theme.swift](Sources/RatioNative/Theme.swift), [RatioTypography.swift](Sources/RatioNative/RatioTypography.swift), [PointingHandCursor.swift](Sources/RatioNative/PointingHandCursor.swift) | Shared colors, typography, button feedback and cursor behavior. |
| [ActivityObservation.swift](Sources/RatioCore/ActivityObservation.swift), [ActivityLedger.swift](Sources/RatioCore/ActivityLedger.swift), [RatioSession.swift](Sources/RatioCore/RatioSession.swift) | Deterministic observations, daily totals, categories and live/demo accounting. |
| [ActivityStore.swift](Sources/RatioCore/ActivityStore.swift), [ActivityCSV.swift](Sources/RatioCore/ActivityCSV.swift), [WebsiteTracking.swift](Sources/RatioCore/WebsiteTracking.swift) | JSON storage/recovery, CSV formatting and website policy. |
| `Tests/RatioCoreTests/`, `Tests/RatioNativeTests/` | Accounting/storage tests and native adapter tests. |
| `Resources/` | Bundle metadata, Automation entitlement and app icon artwork. |
| `scripts/build.sh`, `scripts/package-dmg.sh`, `scripts/verify-release.sh` | Universal app assembly, DMG packaging and release verification. |
| `scripts/generate-icon.swift`, `scripts/generate-dmg-background.swift`, `scripts/configure-dmg-layout.swift` | App icon, installer artwork and Finder metadata generation. |

## Build and run

Use macOS with Xcode or the Command Line Tools and Swift 5.9 or later. The app targets macOS 13 or later.

```sh
swift build
swift test --filter ActivityStoreTests
swift test
```

For manual UI checks, use an isolated data directory and the demo:

```sh
RATIO_NATIVE_DATA_DIR="$PWD/build/agent-demo-data" swift run RatioNative --demo
```

Build and verify a distributable app and DMG:

```sh
./scripts/package-dmg.sh
./scripts/verify-release.sh --app "dist/Open Ratio.app"
```

`./scripts/build.sh` builds only the universal app. `./scripts/package-dmg.sh --skip-build` repackages an existing verified app; use it only when that bundle already includes the intended changes. Build outputs stay in the ignored `build/`, `.build/` and `dist/` directories. Signing is ad hoc by default; `RATIO_SIGN_IDENTITY` selects a Developer ID identity. Packaging does not notarize the app.

## Agent skills

### Issue tracker

Use the local Markdown tracker described in `docs/agents/issue-tracker.md`.

### Domain docs

Read `CONTEXT.md` and relevant `docs/adr/` before changing behavior. Single context; see `docs/agents/domain.md`.

## Working agreements

- Use system frameworks only. Compile regularly with `swift build`; run focused tests while implementing and `swift test` at integrated completion.
- Commit only owned changes to the current branch. The coordinator runs the final two-axis code review against the planning baseline after implementation tickets land.
- Claim a ticket by changing Status to in-progress; mark completed only with acceptance evidence. The parent spec stays unchanged.
- Keep `.scratch/` planning files and ignored documentation local and untracked; never force-add them to Git.

## Coding standards

Use meaningful domain names and small interfaces. Views render state and invoke actions; accounting, persistence and host normalization live outside views. Handle file errors visibly and retain unreadable originals. Avoid force-unwraps except fixed resources with an explained invariant. Time calculations must accept deterministic inputs for tests.

### Naming and clarity

- Use names that explain the domain concept and the operation. Prefer clarity over abbreviations.
- Keep control flow straightforward and helpers focused. Extra lines are useful when they make the behavior easier to follow.
- Explain non-obvious decisions in comments, especially AppKit bridging, time boundaries and native file formats.
- Keep edits within the requested scope. Avoid unrelated refactors, formatting changes and speculative abstractions.

### SwiftUI and concurrency

- Keep shared UI state and view updates on `@MainActor`. Put blocking browser and permission operations on their existing background queues.
- Keep operating-system APIs in `RatioNative`; pass deterministic observations into `RatioCore`.
- Use shared observed state for app data, `@State` for local presentation state and `@Binding` when a child edits parent-owned state. Preserve stable source and day identities in lists.
- Reuse `RatioTheme`, `RatioTypography` and existing button styles. The panel uses 12-point SF Mono, a 1.5 line-height ratio and 0.4-point tracking; text symbols use the shared glyph font.
- Enabled clickable controls show the pointing-hand cursor. Preserve the footer-only white hover treatment and provide meaningful accessibility labels for icon buttons.

## Git workflow

- Inspect status and diffs before editing or staging so existing user changes remain separate.
- Stage owned paths or hunks explicitly. Use concise, imperative commit messages that describe the change.
- Work on the current branch unless the task calls for another branch. Push only when requested; do not force-push the main branch.

## Keeping this file current

Update this file when architecture, important file responsibilities, build commands or user-established conventions change. Keep the key-file map useful when files move or responsibilities change. Record domain terms in `CONTEXT.md` and architectural decisions in `docs/adr/` instead of duplicating those documents here.

Minor edits that do not change this guidance do not need an AGENTS.md update.

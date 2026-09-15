# Ratio Native

A local macOS menu bar app for noticing the balance between **Create** and **Consume**. Its compact 360-point native panel follows the supplied [reference panel](docs/reference-panel.png). SwiftUI and AppKit render the interface; a separate Swift domain accounts for time. There is no webview, network service, account, analytics or third-party dependency.

## Install

1. Open `dist/Ratio-Native-1.0.0-universal.dmg`.
2. Drag **Ratio Native.app** to the **Applications** shortcut.
3. Eject the image and open **Ratio Native** from Applications. The panel opens at launch.
4. Click the ratio in the menu bar to reopen or close the panel. **Right-click the menu bar ratio** for **Settings…**, **How It Works…**, **Try Demo**, **Undo Reset** and **Quit Ratio Native**. The app does not show a Dock icon.

The app targets **macOS 13 or later** and contains both **arm64** and **x86_64** release code. Native runtime verification is limited to the available Apple Silicon Mac running macOS **26.5.2**; Intel hardware and macOS 13 have not been runtime-tested.

The supplied local build is **ad-hoc signed with hardened runtime and is not notarized**. A valid ad-hoc signature verifies integrity but does not establish a Developer ID. If macOS blocks a downloaded copy you trust, attempt to open it, then use its **Open Anyway** entry under **System Settings → Privacy & Security**, as described by [Apple](https://support.apple.com/en-gb/102445). Managed Macs may restrict this action. The build/install scripts do not change macOS security settings or remove quarantine attributes.

To check the downloaded image against its adjacent checksum file:

```sh
cd dist
shasum -a 256 -c Ratio-Native-1.0.0-universal.dmg.sha256
```

## Use the panel

- **↑ Create / ↓ Consume:** classify an app or website using its row controls. Choices apply to its retained time, including previous days. Right-click a source row to make it unclassified again.
- **Ratio:** Create and Consume share classified time only. No classified time displays dashes. The tracked total includes unclassified time; the red badge opens that queue.
- **Pause:** the left footer button pauses or resumes tracking. The clock button opens daily history; select a day to inspect its read-only source rows and use the header's back arrow to return. The footer's list button returns to today's tracking.
- **RESET:** removes today's real durations and preserves categories and previous days. **Undo Reset** restores the most recent nonempty reset, including time tracked since it. Undo is held in memory during the current launch, so use it before quitting or performing another nonempty reset.
- **Appearance:** the right footer button switches light/dark. Settings also offers System appearance.
- **QUIT:** stops the app and saves pending real activity.

The closed menu-bar item shows `NN/NN`. Its icon and text follow the active source: green ↑ for Create, red ↓ for Consume, and white ? for unclassified. Paused tracking shows two white pause bars and white text.

The compact panel and menu-bar ratio use SF Mono at 12 points with 0.4 points of added letter spacing and an 18-point line height. The text symbols `✓`, `↑`, `↓` and `?` use Menlo Regular at 12 points for their compact glyph shapes; the menu-bar symbols and activity-row arrows share this styling. Only the five bottom-bar buttons show a white background with dark labels on hover. The completed-classification `✓` button has a white background while its view is open and returns to its normal appearance when closed.

Foreground activity counts automatically while the app runs. The first five minutes without input count as an idle grace for reading. Sleep, an inactive session and unexplained gaps over ten seconds are excluded; the app never fills time while it was closed. Days use the local date when time was recorded and keep that date after timezone changes.

### Demo and guidance

**Try Demo** uses fictional activity stored separately in memory. **How It Works…** opens a five-step interactive guide with a compact demo panel. Demo mode is labeled **DEMO** in the panel and **D** in the menu bar. You can change demo sources and categories, pause, inspect fictional history and reset it. Real tracking is suspended during demo, and real activity and pause state are preserved. **Exit Demo**, **Close Tour** or **Finish** returns to real activity; resetting the demo never erases real history.

### Optional websites and permissions

Website capture defaults **off for each browser**. In Settings, independently enable Safari, Google Chrome, Microsoft Edge, Brave or Chromium. Supported installed browsers are listed; Safari and previously enabled browsers remain visible. When an enabled browser is foreground, macOS may request **Automation** permission for that browser.

Only HTTP(S) **hostnames** are retained: for example, `https://www.example.com/private?q=secret` becomes `example.com`. Paths, searches, fragments, credentials and page titles are not stored. Each website has its own initially unclassified category; it does not inherit the browser's category. No browser is launched to query it.

Denied access, missing tabs, unsupported URLs and timeouts visibly fall back to **APP TRACKING**. Read the status help or Settings for the reason. To retry a denied browser, allow it in **System Settings → Privacy & Security → Automation**, then select **Retry** in Ratio's Settings or toggle that browser off/on. App tracking requires no Accessibility permission, and website tracking requires no browser JavaScript setting. See [website verification](docs/qa/website-tracking.md) for the supported contract and test scope. Actual browser consent grants are not claimed by the automated tests.

## Local data, recovery and export

| Data | Location |
| --- | --- |
| Real daily activity and remembered categories | `~/Library/Application Support/RatioNative/activity.json` |
| Last valid saved snapshot | `~/Library/Application Support/RatioNative/activity-backup.json` |
| Preserved unreadable originals, if recovery was needed | `~/Library/Application Support/RatioNative/activity-corrupt-<UUID>.json` |
| Appearance and per-browser opt-ins | macOS UserDefaults domain `com.rationative.RatioNative`, normally `~/Library/Preferences/com.rationative.RatioNative.plist` |
| CSV export | A local location you choose in the Save dialog |

Settings has **Show Data Folder**. JSON writes are atomic and retain a previous valid snapshot. Storage errors appear in the panel status and Settings; unreadable originals are preserved. If the app cannot load safely, new activity stays in memory until you fix the reported problem and reopen it. If saving fails, it retains new activity in memory and retries. Copy the entire data folder while the app is quit before manually repairing files; keep any corrupt originals. An unsupported newer schema is left unchanged and requires a compatible app version.

**Export CSV…** is available in Settings and the panel/history context menu. It exports retained days, source names, current categories and seconds. In demo mode it exports only the labeled fictional dataset; leave demo to export real activity. The export is local and does not change activity.

## Build and test

Prerequisites: a Mac, Xcode or Apple Command Line Tools with a macOS SDK, and **Swift 5.9 or later**. The release was built with **Swift 6.2.4** and Xcode's macOS SDK. Swift Package Manager is the project entry point; no downloaded packages are required. If development tools are absent, install them with `xcode-select --install` or install Xcode and complete its first-run setup.

Run from the repository root:

```sh
swift build
swift test
./scripts/build.sh
./scripts/package-dmg.sh
```

`build.sh` compiles optimized arm64 and x86_64 executables with explicit macOS 13.0 targets in separate `build/swiftpm-<architecture>` scratch directories, combines them with `lipo`, supplies the original icon and bundle metadata, and signs with the browser Automation entitlement. It verifies each architecture before replacing `dist/Ratio Native.app`.

`package-dmg.sh` builds again by default so it packages current source. It creates a compressed DMG containing the app, an Applications symlink and an installation note; verifies it; then writes a SHA-256 file. To package an already verified app without rebuilding (for example, a notarized app), run:

```sh
./scripts/package-dmg.sh --skip-build
./scripts/verify-release.sh --app 'dist/Ratio Native.app'
./scripts/verify-release.sh --dmg 'dist/Ratio-Native-1.0.0-universal.dmg'
open 'dist/Ratio Native.app'
```

The verifier checks both architectures, macOS minimum version, menu bar bundle metadata, app icon presence, strict code signatures, hardened runtime and the Apple-events entitlement. For DMGs it also checks image integrity, read-only mounting, the installation note and Applications symlink, then detaches normally. It does not launch the app or claim Gatekeeper/notarization acceptance. Build outputs in `build/`, `.build/` and `dist/` are ignored by Git. To regenerate the original icon:

```sh
swift scripts/generate-icon.swift 'build/RatioNative.iconset'
iconutil -c icns 'build/RatioNative.iconset' -o 'Resources/AppIcon.icns'
```

For an isolated development dataset, launch the executable with `RATIO_NATIVE_DATA_DIR` set to a temporary directory. This overrides activity JSON only; standard appearance and browser preferences still use UserDefaults. `--demo` starts the interactive demo; `--reference-demo` is a frozen visual-QA fixture. Do not mistake the fixture for tracked real activity.

## Troubleshooting

- **Cannot see the app:** find the ratio in the menu bar and click it. Open the app again from Applications to reveal its panel or existing Settings/guide window. Right-click the ratio to quit.
- **No ratio yet:** unknown apps begin unclassified. Select ↑ or ↓; no time or category is invented for a new real dataset.
- **Time stopped advancing:** check Pause, demo mode, input inactivity and session sleep. No activity is reconstructed for time when the app was not running.
- **Website shown as its browser:** check that browser's opt-in and the reason in Settings. Core app tracking continues without website access.
- **Storage error:** open Settings, read the exact path and recovery message, and check access/free space. Keep the original and backup files. Resolve load problems and restart before relying on new in-memory activity being durable.
- **Image is busy during verification/ejection:** close Finder windows or processes using the mounted image, then eject it normally. The verifier prints the remaining mount path if detach fails; it never forces detachment.
- **Build tools missing or wrong compiler:** inspect `xcode-select -p` and `swift --version`, then select an installed compatible Xcode/Command Line Tools installation. Developer ID signing additionally needs your own valid identity in the keychain.

## Optional public signing and notarization

The delivered artifact has **not** been submitted to Apple. Apple Development identities are not a substitute for a **Developer ID Application** identity. The default scripts never submit anything for notarization. The explicit owner-operated workflow, including uploads and verification of an **Accepted** result, is in [Build and public release](docs/build.md).

## Project and evidence

All 34 accounting, persistence, history, demo and website tests pass. The final DMG was mounted, its app copied out and launched on the available Mac; the compact live panel, advancing activity and pause behavior were checked. Runtime and browser-permission limits are recorded in the linked evidence.

- [Accounting vocabulary](CONTEXT.md) and [architecture decisions](docs/adr/)
- [Authoritative specification](.scratch/ratio-native/spec.md) and [implementation tickets](.scratch/ratio-native/issues/)
- [Internal design review](docs/design-review.md), [independent code review](docs/code-review.md) and [verification evidence](docs/verification.md)
- [Compact-panel comparison](docs/qa/compact-panel.md), [website behavior checks](docs/qa/website-tracking.md) and [distribution notes](docs/distribution-notes.md)
- `Sources/RatioCore`: deterministic accounting, history, CSV, persistence and hostname policy
- `Sources/RatioNative`: AppKit/SwiftUI panel, foreground adapters, optional browser Automation and preferences
- `Tests/RatioCoreTests`: concrete accounting timelines and public persistence/browser behavior

### Reference attribution

This is an independent implementation inspired by [Ratio by Visualize Value](https://ratio.visualizevalue.com/) and the publicly observable interactions documented in [reference observations](docs/product-observations.md). It is not the original source, an official distribution or an endorsed product. The supplied screenshot is retained as a design reference; the executable's app icon was created in this repository. No proprietary executable or source was downloaded or reverse engineered.

# Restrict website capture to the system default browser

The user's current choice replaces ADR 0002's per-browser opt-ins with one local “Track websites” setting. Resolve hostnames only when the foreground app is the macOS default HTTPS browser and a supported capture adapter exists. Other browsers retain their own application identities and categories.

Detect default-browser changes during normal foreground sampling and discard prior hosts and in-flight results when the target changes. Unsupported or missing defaults use application tracking with an explanatory Settings status. Detecting the default does not launch a browser or send a network request.

The setting starts off for new installations. When upgrading, inherit only the current default browser's old opt-in; other browsers' saved preferences do not enable it. After migration, the single setting follows whichever browser becomes the default. macOS still governs each target application's Automation permission.

The host-only privacy boundary, request cancellation and timeouts, independent website categories, and existing history remain unchanged. No historical totals are rewritten.

## Explicit access setup

The user's later request adds direct setup to enable/connect/retry actions: open or activate the supported default browser, then request Automation permission immediately, independently of whether a tab exists. Permission requests run off the main thread and keep their native slot until macOS returns. Opt-out and default changes invalidate the result without stacking new requests. A denied grant is explained through the existing Automation Settings link. Background refresh and detection continue without launching applications.

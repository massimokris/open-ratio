# Make website tracking an explicit host-only extension

The browser-selection and opt-in portions are superseded by [ADR 0003](0003-default-browser-websites.md). The host-only privacy and fallback rules remain in force.

App tracking uses the foreground application's public identity and needs no Accessibility permission. Safari and supported Chromium browsers can optionally expose their active tab URL through macOS Automation. Request this only following the user's per-browser enable action, normalize immediately to the hostname, and retain neither full URLs nor page titles. A denied or unavailable browser falls back to app tracking with visible status. A discovered host has its own category rather than inheriting a browser-wide rule.

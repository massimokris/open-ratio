#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 || ( "$1" != --app && "$1" != --dmg ) ]]; then
    echo "Usage: $0 --app '/path/Open Ratio.app' | --dmg '/path/release.dmg'" >&2
    exit 1
fi
ratio_verify_stage="$(mktemp -d "${TMPDIR:-/tmp}/ratio-verify.XXXXXX")"
ratio_mounted=false
ratio_cleanup() {
    if [[ "$ratio_mounted" == true ]]; then
        if ! /usr/bin/hdiutil detach "$ratio_verify_stage/mount"; then
            echo "Could not detach $ratio_verify_stage/mount; eject it normally before removing $ratio_verify_stage." >&2
            return 1
        fi
    fi
    rm -rf -- "$ratio_verify_stage"
}
trap ratio_cleanup EXIT

ratio_verify_app() {
    local ratio_app="$1"
    local ratio_plist="$ratio_app/Contents/Info.plist"
    local ratio_executable="$ratio_app/Contents/MacOS/RatioNative"
    local ratio_arch ratio_build_info ratio_signature
    /usr/bin/plutil -lint "$ratio_plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$ratio_plist")" == "Open Ratio" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$ratio_plist")" == "Open Ratio" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$ratio_plist")" == RatioNative ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ratio_plist")" == com.rationative.RatioNative ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$ratio_plist")" == APPL ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$ratio_plist")" == 13.0 ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$ratio_plist")" == true ]]
    [[ -n "$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$ratio_plist")" ]]
    [[ -s "$ratio_app/Contents/Resources/AppIcon.icns" && -x "$ratio_executable" ]]
    xcrun lipo "$ratio_executable" -verify_arch arm64 x86_64
    /usr/bin/file "$ratio_executable"
    for ratio_arch in arm64 x86_64; do
        ratio_build_info="$(xcrun vtool -arch "$ratio_arch" -show-build "$ratio_executable")"
        [[ "$ratio_build_info" == *"minos 13.0"* ]]
        /usr/bin/codesign --verify --strict --verbose=2 --arch "$ratio_arch" "$ratio_app"
        ratio_signature="$(/usr/bin/codesign --display --verbose=4 --arch "$ratio_arch" "$ratio_app" 2>&1)"
        [[ "$ratio_signature" == *"runtime"* ]]
        /usr/bin/codesign --display --arch "$ratio_arch" --entitlements :- "$ratio_app" \
            > "$ratio_verify_stage/entitlements.plist" 2> "$ratio_verify_stage/signature.log"
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' \
            "$ratio_verify_stage/entitlements.plist")" == true ]]
        echo "Verified $ratio_arch: macOS 13.0 minimum, signature, hardened runtime and browser Automation entitlement."
    done
}

if [[ "$1" == --app ]]; then
    ratio_verify_app "$2"
else
    /usr/bin/hdiutil verify "$2"
    mkdir "$ratio_verify_stage/mount"
    /usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$ratio_verify_stage/mount" "$2"
    ratio_mounted=true
    [[ -L "$ratio_verify_stage/mount/Applications" ]]
    [[ "$(readlink "$ratio_verify_stage/mount/Applications")" == /Applications ]]
    [[ -s "$ratio_verify_stage/mount/Install Open Ratio.txt" ]]
    # A successful write would violate the requested read-only verification mount.
    if touch "$ratio_verify_stage/mount/.ratio-write-check" 2> "$ratio_verify_stage/write-check.log"; then
        rm "$ratio_verify_stage/mount/.ratio-write-check"
        echo "The disk image unexpectedly allowed writes." >&2
        exit 1
    fi
    ratio_verify_app "$ratio_verify_stage/mount/Open Ratio.app"
    /usr/bin/hdiutil detach "$ratio_verify_stage/mount"
    ratio_mounted=false
    echo "Verified DMG integrity, read-only mount, Applications shortcut, installation note and bundled app."
fi

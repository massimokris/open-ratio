#!/bin/bash
set -euo pipefail

ratio_project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ratio_dist_dir="$ratio_project_dir/dist"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --skip-build ) ]]; then
    echo "Usage: $0 [--skip-build]" >&2
    exit 1
fi
if [[ $# -eq 0 ]]; then
    "$ratio_project_dir/scripts/build.sh"
fi

ratio_app="$ratio_dist_dir/Ratio Native.app"
"$ratio_project_dir/scripts/verify-release.sh" --app "$ratio_app"
ratio_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ratio_app/Contents/Info.plist")"
if [[ ! "$ratio_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a three-part numeric app version; found '$ratio_version'." >&2
    exit 1
fi
ratio_dmg_name="Ratio-Native-$ratio_version-universal.dmg"
ratio_package_stage="$(mktemp -d "$ratio_dist_dir/.ratio-package.XXXXXX")"
trap 'rm -rf -- "$ratio_package_stage"' EXIT
mkdir "$ratio_package_stage/image"
/usr/bin/ditto "$ratio_app" "$ratio_package_stage/image/Ratio Native.app"
ln -s /Applications "$ratio_package_stage/image/Applications"
cat > "$ratio_package_stage/image/Install Ratio Native.txt" <<'INSTALL'
RATIO NATIVE — INSTALLATION

1. Drag Ratio Native.app onto the Applications shortcut.
2. Eject this disk image, then open Ratio Native from Applications.
3. The compact panel opens at launch. Click its ratio in the menu bar to reopen it.
   Right-click the menu bar ratio for Settings, How It Works, Try Demo and Quit.

Requires macOS 13 or later. This universal app contains arm64 and x86_64 code.
Activity and preferences stay on your Mac. Website tracking is optional per browser.

The default local build is ad-hoc signed and is not notarized. If macOS blocks a
downloaded copy, first review its source and checksum. For a copy you trust, use
the per-app Open Anyway control in System Settings > Privacy & Security after
attempting to open it. Do not disable Gatekeeper or remove quarantine globally.
Apple's instructions: https://support.apple.com/en-gb/102445

Data folder: ~/Library/Application Support/RatioNative/
Settings includes Show Data Folder and local CSV export.
RESET clears today's real time; Undo Reset restores it during the current launch.
Demo activity is fictional and separate from real history.

See the source project's README.md for builds, permissions, recovery and signing.
This is an independent implementation, not an official Ratio distribution.
INSTALL

/usr/bin/hdiutil create -volname "Ratio Native $ratio_version" \
    -srcfolder "$ratio_package_stage/image" -format UDZO -fs HFS+ \
    -ov "$ratio_package_stage/$ratio_dmg_name"
"$ratio_project_dir/scripts/verify-release.sh" --dmg "$ratio_package_stage/$ratio_dmg_name"
mv -f "$ratio_package_stage/$ratio_dmg_name" "$ratio_dist_dir/$ratio_dmg_name"
(
    cd "$ratio_dist_dir"
    /usr/bin/shasum -a 256 "$ratio_dmg_name" > "$ratio_dmg_name.sha256"
    /usr/bin/shasum -a 256 -c "$ratio_dmg_name.sha256"
)
echo "Packaged: $ratio_dist_dir/$ratio_dmg_name"
echo "Checksum: $ratio_dist_dir/$ratio_dmg_name.sha256"

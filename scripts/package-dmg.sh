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

ratio_app="$ratio_dist_dir/Open Ratio.app"
"$ratio_project_dir/scripts/verify-release.sh" --app "$ratio_app"
ratio_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ratio_app/Contents/Info.plist")"
if [[ ! "$ratio_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a three-part numeric app version; found '$ratio_version'." >&2
    exit 1
fi
ratio_dmg_name="Open-Ratio-$ratio_version-universal.dmg"
ratio_package_stage="$(mktemp -d "$ratio_dist_dir/.ratio-package.XXXXXX")"
ratio_mounted=false
ratio_package_cleanup() {
    if [[ "$ratio_mounted" == true ]]; then
        if ! /usr/bin/hdiutil detach "$ratio_package_stage/mount"; then
            echo "Could not detach $ratio_package_stage/mount; eject it normally before removing $ratio_package_stage." >&2
            return 1
        fi
    fi
    rm -rf -- "$ratio_package_stage"
}
trap ratio_package_cleanup EXIT
mkdir "$ratio_package_stage/image"
/usr/bin/ditto "$ratio_app" "$ratio_package_stage/image/Open Ratio.app"
ln -s /Applications "$ratio_package_stage/image/Applications"
mkdir "$ratio_package_stage/image/.background"
xcrun swift "$ratio_project_dir/scripts/generate-dmg-background.swift" \
    "$ratio_package_stage/image/.background/installer.tiff"

# Create the Finder background alias on the actual image volume so it remains
# valid after compression and when another Mac mounts the finished disk image.
/usr/bin/hdiutil create -volname "Open Ratio $ratio_version" \
    -srcfolder "$ratio_package_stage/image" -format UDRW -fs HFS+ \
    -ov "$ratio_package_stage/layout.dmg"
mkdir "$ratio_package_stage/mount"
/usr/bin/hdiutil attach -readwrite -nobrowse -mountpoint "$ratio_package_stage/mount" \
    "$ratio_package_stage/layout.dmg"
ratio_mounted=true
xcrun swift "$ratio_project_dir/scripts/configure-dmg-layout.swift" "$ratio_package_stage/mount"
/usr/bin/hdiutil detach "$ratio_package_stage/mount"
ratio_mounted=false
/usr/bin/hdiutil convert "$ratio_package_stage/layout.dmg" -format UDZO \
    -o "$ratio_package_stage/$ratio_dmg_name"
"$ratio_project_dir/scripts/verify-release.sh" --dmg "$ratio_package_stage/$ratio_dmg_name"
mv -f "$ratio_package_stage/$ratio_dmg_name" "$ratio_dist_dir/$ratio_dmg_name"
(
    cd "$ratio_dist_dir"
    /usr/bin/shasum -a 256 "$ratio_dmg_name" > "$ratio_dmg_name.sha256"
    /usr/bin/shasum -a 256 -c "$ratio_dmg_name.sha256"
)
echo "Packaged: $ratio_dist_dir/$ratio_dmg_name"
echo "Checksum: $ratio_dist_dir/$ratio_dmg_name.sha256"

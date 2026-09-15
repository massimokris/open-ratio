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
trap 'rm -rf -- "$ratio_package_stage"' EXIT
mkdir "$ratio_package_stage/image"
/usr/bin/ditto "$ratio_app" "$ratio_package_stage/image/Open Ratio.app"
ln -s /Applications "$ratio_package_stage/image/Applications"

/usr/bin/hdiutil create -volname "Open Ratio $ratio_version" \
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

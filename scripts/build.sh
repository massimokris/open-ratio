#!/bin/bash
set -euo pipefail

ratio_project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ratio_dist_dir="$ratio_project_dir/dist"
ratio_sign_identity="${RATIO_SIGN_IDENTITY:--}"

if [[ "$(uname -s)" != Darwin ]]; then
    echo "Ratio Native must be built on macOS with Xcode or Command Line Tools." >&2
    exit 1
fi
if [[ "$ratio_sign_identity" != - && "$ratio_sign_identity" != "Developer ID Application: "* ]]; then
    echo "Use '-' for ad-hoc signing or your full Developer ID Application identity." >&2
    exit 1
fi

mkdir -p "$ratio_dist_dir"
ratio_build_stage="$(mktemp -d "$ratio_dist_dir/.ratio-build.XXXXXX")"
trap 'rm -rf -- "$ratio_build_stage"' EXIT
ratio_app="$ratio_build_stage/Ratio Native.app"
mkdir -p "$ratio_app/Contents/MacOS" "$ratio_app/Contents/Resources"
ratio_sdk="$(xcrun --sdk macosx --show-sdk-path)"
ratio_binaries=()

for ratio_arch in arm64 x86_64; do
    ratio_scratch="$ratio_project_dir/build/swiftpm-$ratio_arch"
    ratio_triple="$ratio_arch-apple-macosx13.0"
    echo "Building release for $ratio_arch (macOS 13.0 minimum)…"
    xcrun swift build --package-path "$ratio_project_dir" --scratch-path "$ratio_scratch" \
        --configuration release --product RatioNative --triple "$ratio_triple" --sdk "$ratio_sdk"
    ratio_binary_dir="$(xcrun swift build --package-path "$ratio_project_dir" --scratch-path "$ratio_scratch" \
        --configuration release --triple "$ratio_triple" --sdk "$ratio_sdk" --show-bin-path)"
    ratio_binaries+=("$ratio_binary_dir/RatioNative")
done

xcrun lipo -create "${ratio_binaries[@]}" -output "$ratio_app/Contents/MacOS/RatioNative"
chmod 755 "$ratio_app/Contents/MacOS/RatioNative"
cp "$ratio_project_dir/Resources/Info.plist" "$ratio_app/Contents/Info.plist"
cp "$ratio_project_dir/Resources/AppIcon.icns" "$ratio_app/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$ratio_app/Contents/PkgInfo"

ratio_sign_options=(--force --sign "$ratio_sign_identity" --options runtime \
    --entitlements "$ratio_project_dir/Resources/RatioNative.entitlements")
if [[ "$ratio_sign_identity" == - ]]; then
    ratio_sign_options+=(--timestamp=none)
else
    ratio_sign_options+=(--timestamp)
fi
/usr/bin/codesign "${ratio_sign_options[@]}" "$ratio_app"
"$ratio_project_dir/scripts/verify-release.sh" --app "$ratio_app"

# Replace only this script's generated bundle, after a successful build and verification.
rm -rf -- "$ratio_dist_dir/Ratio Native.app"
mv "$ratio_app" "$ratio_dist_dir/Ratio Native.app"
echo "Built: $ratio_dist_dir/Ratio Native.app"
if [[ "$ratio_sign_identity" == - ]]; then
    echo "Signing: ad hoc with hardened runtime; not notarized."
else
    echo "Signing: Developer ID with hardened runtime; notarization is a separate opt-in step."
fi

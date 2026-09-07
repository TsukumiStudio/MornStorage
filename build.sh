#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
build_args=(-c release)
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    build_args+=(--arch arm64 --arch x86_64)
fi
swift build "${build_args[@]}"
binary_dir=$(swift build "${build_args[@]}" --show-bin-path)
app_path="$PWD/dist/MornStorage.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/MornStorage" "$app_path/Contents/MacOS/MornStorage"
cp Support/Info.plist "$app_path/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    [[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid VERSION'; exit 1; }
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$app_path/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$app_path/Contents/Info.plist"
fi
# A Developer ID signature keeps the app's identity stable across rebuilds, so TCC remembers
# granted folder access; ad-hoc signing changes identity every build and re-prompts each launch.
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"')}"
codesign --force --sign "${identity:--}" --identifier studio.tsukumi.MornStorage "$app_path"
print "Signed with: ${identity:-ad-hoc}"
print "Built: $app_path"

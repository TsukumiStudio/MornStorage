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
codesign --force --sign - --identifier studio.tsukumi.MornStorage "$app_path"
print "Built: $app_path"

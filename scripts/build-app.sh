#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
if [[ -n "${LITECONTROL_MACOS_SDK:-}" ]]; then sdk="$LITECONTROL_MACOS_SDK"; fi
swift build -c release --sdk "$sdk"
mkdir -p build
staging_dir="$(mktemp -d build/.litecontrol-build.XXXXXX)"
trap 'rm -rf "$staging_dir"' EXIT
app="$staging_dir/LiteControl.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/LiteControl "$app/Contents/MacOS/LiteControl"
mkdir -p "$app/Contents/Resources"
cp -R Support/ProductIcons Support/*.lproj "$app/Contents/Resources/"
cp Support/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
rm -rf build/LiteControl.app
mv "$app" build/LiteControl.app
echo "$PWD/build/LiteControl.app"

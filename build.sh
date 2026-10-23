#!/bin/sh
# Builds ClaudeDeck.app (release, for this Mac's architecture, ad-hoc signed) in the repo root.
# Version comes from $VERSION, else the latest git tag (without the "v"), else 0.0.0.
set -e
cd "$(dirname "$0")"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
swift build -c release
bin=$(swift build -c release --show-bin-path)
app=ClaudeDeck.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/ClaudeDeck" "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
cp scripts/hook.sh "$app/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app ($VERSION)"

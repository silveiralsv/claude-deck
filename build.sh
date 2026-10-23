#!/bin/sh
# Builds ClaudeDeck.app (release, ad-hoc signed) in the repo root.
set -e
cd "$(dirname "$0")"
swift build -c release
app=ClaudeDeck.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/ClaudeDeck "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
cp scripts/hook.sh "$app/Contents/Resources/"
codesign --force --sign - "$app"
echo "Built $app"

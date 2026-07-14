#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
app="dist/AI Usage Widget.app"

swift build -c release
rm -rf AIUsageWidget.app
rm -rf dist
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64-apple-macosx/release/AIUsageWidget "$app/Contents/MacOS/AIUsageWidget"
cp Packaging/Info.plist "$app/Contents/Info.plist"
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
xattr -cr "$app"
codesign --force --sign - "$app"
(cd dist && /usr/bin/zip -r -X AIUsageWidget-macOS.zip "AI Usage Widget.app" >/dev/null)
codesign --verify --deep --strict "$app"
echo "$PWD/$app"

#!/bin/bash
# Packages build/NachoCombo.app into dist/ as zip + dmg + SHA256SUMS.txt.
# Usage: VERSION=0.1.0 scripts/package.sh   (run scripts/build-app.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:?set VERSION, e.g. VERSION=0.1.0}"
APP="build/NachoCombo.app"
[ -d "$APP" ] || { echo "missing $APP; run scripts/build-app.sh first" >&2; exit 1; }
rm -rf dist && mkdir dist
ditto -c -k --keepParent "$APP" "dist/NachoCombo-$VERSION-macos.zip"
hdiutil create -volname "Nacho Combo" -srcfolder "$APP" -ov -format UDZO "dist/NachoCombo-$VERSION-macos.dmg"
(cd dist && shasum -a 256 "NachoCombo-$VERSION-macos.zip" "NachoCombo-$VERSION-macos.dmg" > SHA256SUMS.txt)
ls -l dist
cat dist/SHA256SUMS.txt

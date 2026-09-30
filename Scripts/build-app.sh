#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH=/tmp/calendarmaker-clang-cache
export SWIFT_MODULE_CACHE_PATH=/tmp/calendarmaker-swift-cache

swift build --disable-sandbox --scratch-path .build -c release

app_path="${PWD}/dist/CalendarMaker.app"
binary_path="${PWD}/.build/arm64-apple-macosx/release"
rm -rf "${app_path}"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"
cp "${binary_path}/CalendarMaker" "${app_path}/Contents/MacOS/CalendarMaker"
cp "${binary_path}/CalendarMaker_CalendarMaker.bundle/holidays.csv" "${app_path}/Contents/Resources/holidays.csv"

cat > "${app_path}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>ja</string>
  <key>CFBundleExecutable</key><string>CalendarMaker</string>
  <key>CFBundleIdentifier</key><string>jp.uruly.CalendarMaker</string>
  <key>CFBundleName</key><string>カレンダーメーカー</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "${app_path}"
echo "Built ${app_path}"

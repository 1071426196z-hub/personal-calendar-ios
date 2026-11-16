#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$root/ios/build-output}"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
mkdir -p "$output" "$build/staging/Payload"

xcodebuild -project "$root/ios/PersonalCalendar.xcodeproj" -scheme PersonalCalendar \
  -configuration Release -destination "generic/platform=iOS" -sdk iphoneos \
  -derivedDataPath "$build/derived" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

app="$build/derived/Build/Products/Release-iphoneos/PersonalCalendar.app"
binary="$app/PersonalCalendar"
test "$(lipo -archs "$binary")" = arm64
test "$(plutil -extract MinimumOSVersion raw "$app/Info.plist")" = 27.0
test -f "$app/lunar-1.7.8.js" -a -f "$app/dates.js" -a -f "$app/NativeBridge.js"
widget="$app/PlugIns/PersonalCalendarWidgets.appex"
test "$(lipo -archs "$widget/PersonalCalendarWidgets")" = arm64
test "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$widget/Info.plist")" = com.apple.widgetkit-extension
test -f "$widget/lunar-1.7.8.js" -a -f "$widget/dates.js" -a -f "$widget/NativeBridge.js"
plutil -extract NSRemindersFullAccessUsageDescription raw "$app/Info.plist" >/dev/null
plutil -extract NSCalendarsFullAccessUsageDescription raw "$app/Info.plist" >/dev/null
ditto "$app" "$build/staging/Payload/PersonalCalendar.app"
ditto -c -k --keepParent "$build/staging/Payload" "$build/PersonalCalendar.ipa"
unzip -tq "$build/PersonalCalendar.ipa"
mv -f "$build/PersonalCalendar.ipa" "$output/PersonalCalendar.ipa"
(cd "$output" && shasum -a 256 PersonalCalendar.ipa > PersonalCalendar.ipa.sha256)

#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BUILD="$ROOT/build"
APP="$BUILD/Local LLM Usage.app"
WIDGET="$APP/Contents/PlugIns/LocalLLMUsageWidget.appex"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$WIDGET/Contents/MacOS"

/usr/bin/swiftc -parse-as-library -O \
  -o "$APP/Contents/MacOS/LocalLLMUsage" \
  "$ROOT/Sources/App/AppMain.swift" \
  "$ROOT/Sources/Core/MetricsParser.swift" \
  -framework AppKit -framework Charts -framework Foundation -framework SwiftUI -framework UniformTypeIdentifiers -framework WidgetKit

/usr/bin/swiftc -parse-as-library -application-extension -O \
  -o "$WIDGET/Contents/MacOS/LocalLLMUsageWidget" \
  "$ROOT/Sources/Widget/Widget.swift" \
  -framework Foundation -framework SwiftUI -framework WidgetKit

/usr/bin/ditto "$ROOT/Resources/App-Info.plist" "$APP/Contents/Info.plist"
/usr/bin/ditto "$ROOT/Resources/Widget-Info.plist" "$WIDGET/Contents/Info.plist"

/usr/bin/codesign --force --sign - --entitlements "$ROOT/Resources/Widget.entitlements" "$WIDGET"
/usr/bin/codesign --force --sign - --entitlements "$ROOT/Resources/App.entitlements" "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
echo "$APP"

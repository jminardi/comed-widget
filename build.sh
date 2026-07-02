#!/bin/bash
# One-shot build/assemble/sign/install for the ComEd Hourly Pricing widget.
# No Xcode required: compiles with swiftc against the Command Line Tools SDK,
# hand-assembles the .app + .appex bundle, ad-hoc codesigns, and
# installs to /Applications (falling back to ~/Applications).
#
# The appex uses the classic NSExtension layout (Contents/PlugIns +
# NSExtension/NSExtensionPointIdentifier). The ExtensionKit layout
# (Contents/Extensions + EXAppExtensionAttributes) registers with pluginkit but
# chronod's descriptor query fails: the appex exits(0) during the
# _EXRunningExtension check-in before answering `getAllDescriptors`, so the
# widget never shows in the gallery. Working third-party widgets on macOS 15
# (e.g. Todoist) use the classic layout.
#
# Requirements: macOS 14+, Command Line Tools (swiftc). Builds for the native
# architecture of the machine running the script.
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJ/Sources"
BUILD="$PROJ/build"
# SDK: use the active toolchain's macOS SDK (works with plain Command Line
# Tools or full Xcode). Override with SDK=/path/to/MacOSX.sdk if needed.
SDK="${SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
SDKVER="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 15.0)"
# Build for the native architecture (arm64 on Apple Silicon, x86_64 on Intel).
ARCH="$(uname -m)"
MINVER="14.0"
TARGET="$ARCH-apple-macosx$MINVER"

APP_ID="org.minardi.comed-prices"
WIDGET_ID="org.minardi.comed-prices.widget"

APP_NAME="ComEdPrices"
WIDGET_NAME="ComEdWidget"

# Install location: /Applications if writable, else ~/Applications.
if [ -w /Applications ]; then INSTALL_DIR=/Applications; else INSTALL_DIR="$HOME/Applications"; mkdir -p "$INSTALL_DIR"; fi
APP="$INSTALL_DIR/$APP_NAME.app"

echo "==> Cleaning"
rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "==> Compiling widget extension binary"
# -e _NSExtensionMain: appex binaries must enter through Foundation's
# NSExtensionMain (as Xcode links them), which performs the extension host
# check-in and services XPC forever. With the default @main entry the WidgetKit
# runtime exits(0) after setup, before chronod's getAllDescriptors is answered.
swiftc -parse-as-library -O -target "$TARGET" -sdk "$SDK" \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -framework Foundation \
  -o "$BUILD/$WIDGET_NAME" \
  "$SRC/ComEdData.swift" "$SRC/PriceChartView.swift" "$SRC/Widget.swift"

echo "==> Compiling host app binary"
swiftc -O -target "$TARGET" -sdk "$SDK" \
  -o "$BUILD/$APP_NAME" \
  "$SRC/ComEdData.swift" "$SRC/PriceChartView.swift" "$SRC/App.swift"

echo "==> Assembling bundle at staging"
STAGE="$BUILD/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS"
mkdir -p "$STAGE/Contents/Resources"
APPEX="$STAGE/Contents/PlugIns/$WIDGET_NAME.appex"
mkdir -p "$APPEX/Contents/MacOS"

cp "$BUILD/$APP_NAME" "$STAGE/Contents/MacOS/$APP_NAME"
cp "$BUILD/$WIDGET_NAME" "$APPEX/Contents/MacOS/$WIDGET_NAME"

# ---- Host app Info.plist ----
cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ComEd Prices</string>
  <key>CFBundleDisplayName</key><string>ComEd Prices</string>
  <key>CFBundleIdentifier</key><string>$APP_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>$MINVER</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# ---- Widget appex Info.plist (classic NSExtension, matches working widgets) ----
cat > "$APPEX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ComEd Widget</string>
  <key>CFBundleDisplayName</key><string>ComEd Hourly Pricing</string>
  <key>CFBundleIdentifier</key><string>$WIDGET_ID</string>
  <key>CFBundleExecutable</key><string>$WIDGET_NAME</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleSupportedPlatforms</key>
  <array><string>MacOSX</string></array>
  <key>DTPlatformName</key><string>macosx</string>
  <key>DTSDKName</key><string>macosx$SDKVER</string>
  <key>DTPlatformVersion</key><string>$SDKVER</string>
  <key>LSMinimumSystemVersion</key><string>$MINVER</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
PLIST

# ---- Entitlements ----
ENT_APP="$BUILD/app.entitlements"
ENT_WIDGET="$BUILD/widget.entitlements"
cat > "$ENT_APP" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
cp "$ENT_APP" "$ENT_WIDGET"

echo "==> Codesigning (appex first, then app) ad-hoc"
codesign --force --timestamp=none -s - --entitlements "$ENT_WIDGET" "$APPEX"
codesign --force --timestamp=none -s - --entitlements "$ENT_APP" "$STAGE"

echo "==> Installing to $APP"
# Kill any running instance so we can overwrite cleanly.
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
rm -rf "$APP"
ditto "$STAGE" "$APP"

echo "==> Verifying codesign"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 || true
codesign -dv --verbose=2 "$APP/Contents/PlugIns/$WIDGET_NAME.appex" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true

echo "==> Registering with LaunchServices"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$LSREGISTER" -f "$APP" || true

echo "==> Launching host app once to register the extension"
open -a "$APP" || open "$APP" || true
sleep 4

echo "==> pluginkit registration check"
pluginkit -mv -p com.apple.widgetkit-extension 2>/dev/null | grep -i comed || echo "(not yet listed — see README troubleshooting)"

# Refresh the widget daemon (populates the gallery) and Notification Center.
killall chronod 2>/dev/null || true
sleep 2
killall NotificationCenter 2>/dev/null || true

echo "==> Done. Installed at: $APP"

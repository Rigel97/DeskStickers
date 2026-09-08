#!/bin/bash
# 构建 release 版本并组装 DeskStickers.app（含程序化生成的图标与 ad-hoc 签名）。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DeskStickers"
BUNDLE_ID="com.deskstickers.mac"
OUT_DIR="build"
APP_PATH="$OUT_DIR/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> 生成图标"
ICON_1024="$(mktemp -d)/icon-1024.png"
swift Scripts/make-icon.swift "$ICON_1024" >/dev/null
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for dimension in 16 32 64 128 256 512; do
  sips -z $dimension $dimension "$ICON_1024" --out "$ICONSET/icon_${dimension}x${dimension}.png" >/dev/null
  double=$((dimension * 2))
  if [ $double -le 1024 ]; then
    sips -z $double $double "$ICON_1024" --out "$ICONSET/icon_${dimension}x${dimension}@2x.png" >/dev/null
  fi
done
sips -z 1024 1024 "$ICON_1024" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
ICON_PATH="$OUT_DIR/AppIcon.icns"
mkdir -p "$OUT_DIR"
iconutil -c icns "$ICONSET" -o "$ICON_PATH"

echo "==> 组装 $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$ICON_PATH" "$APP_PATH/Contents/Resources/AppIcon.icns"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>桌面贴纸</string>
    <key>CFBundleDisplayName</key>
    <string>桌面贴纸</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP_PATH" >/dev/null 2>&1 || codesign --force --sign - "$APP_PATH"

echo "完成: $APP_PATH"

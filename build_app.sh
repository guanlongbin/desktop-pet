#!/bin/bash
# 把 SwiftPM 产物打包成可拖动的 DesktopPet.app
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DesktopPet"
APP_DISPLAY="桌面小机器人"
BUNDLE_ID="com.guanlongbin.desktoppet"
VERSION="1.0.1"

echo "==> 编译 release 二进制"
swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)
EXEC_SRC="$BIN_PATH/$APP_NAME"
BUNDLE_SRC="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"

if [ ! -f "$EXEC_SRC" ]; then
  echo "找不到可执行文件: $EXEC_SRC" >&2
  exit 1
fi

DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> 重建 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "==> 拷贝可执行文件"
cp "$EXEC_SRC" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [ -d "$BUNDLE_SRC" ]; then
  echo "==> 拷贝资源 bundle"
  cp -R "$BUNDLE_SRC" "$RES_DIR/"
fi

echo "==> 写入 Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> 移除隔离属性"
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

echo "==> 临时签名"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo ""
echo "完成: $APP_DIR"

echo ""
echo "==> 打包 DMG"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
STAGE_DIR="$DIST_DIR/.dmg-stage"
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$APP_DIR" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
    -volname "$APP_DISPLAY" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format ULFO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGE_DIR"

echo "完成: $DMG_PATH"
echo ""
echo "下一步:"
echo "  1. 双击 $DMG_PATH"
echo "  2. 在弹出的窗口里把 $APP_NAME.app 拖到 Applications"
echo "  3. 启动台找到 $APP_DISPLAY 双击运行"
echo "  4. 想开机自启 → 系统设置 → 通用 → 登录项 → 加它"

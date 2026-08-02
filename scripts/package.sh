#!/usr/bin/env bash
# =============================================================================
# no-command 打包脚本
# 生成：Release 构建 + 签名校验 + zip + dmg（本机使用 / 局域网分发）
#
# 用法：
#   ./scripts/package.sh
# 产物：
#   dist/no-command-<版本>.zip   （通用分发：微信 / AirDrop / 网盘）
#   dist/no-command-<版本>.dmg   （标准安装体验：拖入 Applications）
#
# 对外分发注意（本脚本不做）：
#   zip/dmg 发给别人时，对方 Gatekeeper 会拦截「未公证」的 App，需要：
#   1) Apple Developer 付费账号申请 Developer ID Application 证书
#   2) 签名：codesign --options runtime --timestamp --deep \
#        -s "Developer ID Application: <你的名字>" no-command.app
#   3) 公证：xcrun notarytool submit dist/no-command-<版本>.zip \
#        --apple-id <你的 Apple ID> --password <app专用密码> --team-id <团队ID>
#   4) 装订：xcrun stapler staple no-command.app   （在 dmg 制作前执行）
#   仅自己用/公司内网：上面的都不需要，本机直接拷贝 .app 或安装 dmg 即可。
# =============================================================================
set -euo pipefail

# 切换到仓库根目录（脚本所在目录的上一级）
cd "$(dirname "$0")/.."

SCHEME="no-command"
CONFIG="Release"
BUILD_DIR="build"
DIST_DIR="dist"
APP_NAME="no-command"

echo "==> 1/4 Release 构建"
xcodebuild -project no-command.xcodeproj -scheme "$SCHEME" \
  -configuration "$CONFIG" -derivedDataPath "$BUILD_DIR" build

APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
[ -d "$APP" ] || { echo "构建产物不存在: $APP"; exit 1; }

# 版本号取构建产物的 Info.plist，避免脚本与工程配置两处维护
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
# 注意：${VERSION} 必须加花括号——后面紧跟全角括号「）」时，bash 会把多字节字符误并入变量名
echo "==> 2/4 校验签名与 Info.plist（版本 ${VERSION}）"
codesign --verify --deep --strict "$APP" && echo "    签名校验通过"
/usr/libexec/PlistBuddy \
  -c "Print :CFBundleDisplayName" \
  -c "Print :CFBundleIdentifier" \
  -c "Print :LSUIElement" \
  "$APP/Contents/Info.plist"

echo "==> 3/4 打包 zip + dmg"
rm -rf "$DIST_DIR" && mkdir -p "$DIST_DIR"

# zip：通用分发格式（保留符号链接与权限）
ditto -c -k --keepParent "$APP" "$DIST_DIR/${APP_NAME}-${VERSION}.zip"

# dmg：标准「拖入 Applications」安装体验（内含 /Applications 软链）
STAGE_DIR="$(mktemp -d)"
cp -R "$APP" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" \
  -ov -format UDZO "$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
rm -rf "$STAGE_DIR"

echo "==> 4/4 完成"
ls -lh "$DIST_DIR"

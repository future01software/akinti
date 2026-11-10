#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Sürüm: VERSION ortam değişkeni (GitHub'da etiketten gelir, ör. v0.7.0 -> 0.7.0); yoksa son git etiketi; o da yoksa 0.0.0-dev.
VERSION="${VERSION:-$( (git describe --tags --abbrev=0 2>/dev/null || true) | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_OPTIONS=(--scratch-path .build/bundle)
case "$(swift build --help)" in
    *swiftbuild*) BUILD_OPTIONS+=(--build-system swiftbuild) ;;
esac
swift build "${BUILD_OPTIONS[@]}" -c release
BIN="$(swift build "${BUILD_OPTIONS[@]}" -c release --show-bin-path)"
STAGING="$(mktemp -d /tmp/akinti-build.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Akıntı.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Akinti" "$APP/Contents/MacOS/Akinti"
# Simge: scripts/make-icon.swift ile üretilir (bkz. README).
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Lisanslar ve torrent bileşeni (aria2 + kütüphaneleri; bkz. Licenses/THIRD-PARTY.md)
cp -R Licenses "$APP/Contents/Resources/Licenses"
./scripts/bundle-aria2.sh "$APP"
# Tarayıcı eklentisi: Native Messaging köprüsü ve eklenti klasörü (Ayarlar → Tarayıcı eklentisi)
mkdir -p "$APP/Contents/Helpers"
cp "$BIN/akinti-bridge" "$APP/Contents/Helpers/akinti-bridge"
codesign --force --sign - "$APP/Contents/Helpers/akinti-bridge" >/dev/null 2>&1
cp -R Extension/chrome "$APP/Contents/Resources/ChromeExtension"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Akinti</string>
<key>CFBundleIdentifier</key><string>org.akinti.downloads</string>
<key>CFBundleName</key><string>Akıntı</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>org.akinti.magnet</string>
  <key>CFBundleURLSchemes</key><array><string>magnet</string></array>
</dict><dict>
  <key>CFBundleURLName</key><string>org.akinti.add</string>
  <key>CFBundleURLSchemes</key><array><string>akinti</string></array>
</dict></array>
<key>CFBundleDocumentTypes</key><array><dict>
  <key>CFBundleTypeName</key><string>BitTorrent</string>
  <key>CFBundleTypeRole</key><string>Viewer</string>
  <key>LSHandlerRank</key><string>Alternate</string>
  <key>CFBundleTypeExtensions</key><array><string>torrent</string></array>
  <key>LSItemContentTypes</key><array><string>org.bittorrent.torrent</string></array>
</dict></array>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist
# Zip only regular file data: Finder and cloud-provider attributes are not archived.
python3 - "$APP" "dist/Akinti-macOS.zip" <<'PYZIP'
import pathlib, sys, zipfile
app = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(app.parent))
PYZIP
# Tarayıcı eklentisi ayrı zip olarak da (Chrome Web Store'a yükleme ve "Paketlenmemiş öğe yükle" için).
python3 - Extension/chrome "dist/Akinti-Chrome-Extension.zip" <<'PYZIP'
import pathlib, sys, zipfile
root = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob('*')):
        if path.is_file() and path.name != '.DS_Store':
            archive.write(path, path.relative_to(root))
PYZIP
# Keep a convenient local app alongside the verified distribution archive.
/usr/bin/ditto --norsrc --noextattr "$APP" "dist/Akıntı.app"
echo "Hazır: dist/Akinti-macOS.zip (sürüm $VERSION, imzası doğrulanmış paket) ve dist/Akinti-Chrome-Extension.zip"

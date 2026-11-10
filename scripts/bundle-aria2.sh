#!/bin/bash
# aria2c'yi ve Homebrew kütüphanelerini uygulama paketine kopyalar, böylece torrent Homebrew'suz çalışır.
#   Kullanım: scripts/bundle-aria2.sh <Akıntı.app>
#   - aria2c          -> Contents/Helpers/aria2c
#   - bağımlı .dylib  -> Contents/Frameworks/  (yollar @executable_path/../Frameworks olarak yeniden yazılır)
# Sistem kütüphaneleri (/usr/lib, /System) kopyalanmaz. aria2 bulunamazsa uyarı verip çıkar (uygulama yine çalışır).
set -euo pipefail
APP="${1:?Akıntı.app yolu gerekli}"
SRC="$(command -v aria2c || true)"
[ -z "$SRC" ] && [ -x /opt/homebrew/bin/aria2c ] && SRC=/opt/homebrew/bin/aria2c
if [ -z "$SRC" ]; then
    echo "uyarı: aria2c bulunamadı; torrent desteği pakete eklenmedi (brew install aria2)" >&2
    exit 0
fi
SRC="$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$SRC")"
HELPERS="$APP/Contents/Helpers"; LIBS="$APP/Contents/Frameworks"
mkdir -p "$HELPERS" "$LIBS"
cp "$SRC" "$HELPERS/aria2c"; chmod 755 "$HELPERS/aria2c"

# Homebrew'dan gelen bağımlılıkları (ve onların bağımlılıklarını) bul.
deps() { otool -L "$1" | awk 'NR>1 {print $1}' | grep -E '^/(opt/homebrew|usr/local)/' || true; }
realpath_of() { python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
queue=("$HELPERS/aria2c"); seen=" "
while [ ${#queue[@]} -gt 0 ]; do
    file="${queue[0]}"; queue=("${queue[@]:1}")
    for dep in $(deps "$file"); do
        name="$(basename "$dep")"
        case "$file" in
            "$HELPERS/aria2c") install_name_tool -change "$dep" "@executable_path/../Frameworks/$name" "$file" 2>/dev/null ;;
            *)                 install_name_tool -change "$dep" "@loader_path/$name" "$file" 2>/dev/null ;;
        esac
        if [[ "$seen" != *" $name "* ]]; then
            seen="$seen$name "
            cp "$(realpath_of "$dep")" "$LIBS/$name"; chmod 644 "$LIBS/$name"
            install_name_tool -id "@rpath/$name" "$LIBS/$name"
            queue+=("$LIBS/$name")
        fi
    done
done

# OpenSSL'in "legacy" sağlayıcı modülü (Homebrew yolunda aranır; pakete alınır, TorrentEngine OPENSSL_MODULES ile gösterir).
for candidate in /opt/homebrew/opt/openssl@4/lib/ossl-modules/legacy.dylib /opt/homebrew/opt/openssl@3/lib/ossl-modules/legacy.dylib; do
    if [ -f "$candidate" ]; then
        mkdir -p "$LIBS/ossl-modules"
        cp "$(realpath_of "$candidate")" "$LIBS/ossl-modules/legacy.dylib"; chmod 644 "$LIBS/ossl-modules/legacy.dylib"
        for dep in $(deps "$LIBS/ossl-modules/legacy.dylib"); do
            install_name_tool -change "$dep" "@loader_path/../$(basename "$dep")" "$LIBS/ossl-modules/legacy.dylib"
        done
        codesign --force --sign - "$LIBS/ossl-modules/legacy.dylib" >/dev/null
        break
    fi
done

# install_name_tool imzayı bozar: her parçayı yeniden (ad hoc) imzala.
for lib in "$LIBS"/*.dylib; do codesign --force --sign - "$lib" >/dev/null; done
codesign --force --sign - "$HELPERS/aria2c" >/dev/null 2>&1

# Kontrol: Homebrew yoluna bağımlılık kalmamalı.
if otool -L "$HELPERS/aria2c" "$LIBS"/*.dylib "$LIBS"/ossl-modules/*.dylib 2>/dev/null | grep -qE '/(opt/homebrew|usr/local)/'; then
    echo "hata: pakette hâlâ Homebrew yoluna bağımlılık var" >&2; exit 1
fi
echo "aria2 pakete eklendi: $(basename "$SRC") + $(ls "$LIBS" | wc -l | tr -d ' ') kütüphane"

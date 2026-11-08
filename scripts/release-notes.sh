#!/bin/bash
# CHANGELOG.md'den bir sürümün bölümünü yazdırır.  Kullanım: scripts/release-notes.sh 0.7.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?sürüm numarası gerekli, ör. 0.7.0}"
awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^## \[/ { exit }
  found && /^\[[^]]+\]: / { exit }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d' | awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] == "") n--; for (i = 1; i <= n; i++) print lines[i] }'
echo
echo "Tüm değişiklikler: [CHANGELOG.md](https://github.com/future01software/akinti/blob/main/CHANGELOG.md)"

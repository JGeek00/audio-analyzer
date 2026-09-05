#!/bin/bash
# ponytail: hdiutil basta, sin create-dmg ni fondo custom. Agrega eso cuando el DMG necesite branding.
set -euo pipefail

# App ya notarizada (exportada desde Organizer). Uso:
#   scripts/make-dmg.sh ["/ruta/a/Audio Analyzer.app"] ["salida.dmg"]
# En Xcode se pasa como DMG_APP_PATH o primer argumento del Run Script.
PROJ_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
APP="${1:-${DMG_APP_PATH:-$PROJ_DIR/dist/Audio Analyzer.app}}"
[[ -d "$APP" ]] || { echo "error: no existe '$APP'. Exporta la app notarizada ahi o pasa su ruta como argumento." >&2; exit 1; }

# Falla rapido si la entrada no esta firmada (evita distribuir un DMG roto).
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
OUT="${2:-$PROJ_DIR/dist/AudioAnalyzer-$VERSION.dmg}"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$(dirname "$OUT")"
hdiutil create -volname "Audio Analyzer" -srcfolder "$STAGING" -ov -format UDZO "$OUT"
echo "DMG listo: $OUT"

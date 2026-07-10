#!/usr/bin/env bash
# 1024x1024 のマスターアイコンから macOS AppIcon を生成
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/Echo/Assets.xcassets/AppIcon.appiconset/icon-1024.png}"
ICONSET="$ROOT/Echo/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SRC" ]]; then
  echo "Source icon not found: $SRC" >&2
  exit 1
fi

mkdir -p "$ICONSET"

generate() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$SRC" --out "$ICONSET/$name" >/dev/null
}

generate 16 icon_16x16.png
generate 32 icon_16x16@2x.png
generate 32 icon_32x32.png
generate 64 icon_32x32@2x.png
generate 128 icon_128x128.png
generate 256 icon_128x128@2x.png
generate 256 icon_256x256.png
generate 512 icon_256x256@2x.png
generate 512 icon_512x512.png
cp "$SRC" "$ICONSET/icon_512x512@2x.png"

cat > "$ICONSET/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

echo "✅ App icons generated in $ICONSET"

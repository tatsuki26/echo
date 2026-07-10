#!/usr/bin/env zsh
# 用意した PNG アイコンを AppIcon.appiconset に配置する
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMPORT_PATH="${1:-$ROOT/assets/AppIcon-import}"
ICONSET="$ROOT/Echo/Assets.xcassets/AppIcon.appiconset"

pick_source_dir() {
  local input="${1:-}"

  if [[ -f "$input" && "$input" =~ '\.(png|PNG|jpg|JPG|jpeg|JPEG)$' ]]; then
    echo "${input:h}"
    return
  fi

  if [[ -n "$input" && -d "$input" && -n "$(find "$input" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print -quit 2>/dev/null)" ]]; then
    echo "$input"
    return
  fi

  osascript <<'APPLESCRIPT'
set chosenFolder to choose folder with prompt "アイコン PNG が入ったフォルダを選択してください"
POSIX path of chosenFolder
APPLESCRIPT
}

SOURCE_DIR="$(pick_source_dir "$IMPORT_PATH")"
SOURCE_DIR="${SOURCE_DIR//$'\n'/}"
SOURCE_DIR="${SOURCE_DIR%%$'\r'*}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "フォルダが見つかりません: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$ICONSET"
typeset -A SOURCES

for file in "$SOURCE_DIR"/*.(png|PNG|jpg|JPG|jpeg|JPEG)(N); do
  width=$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  height=$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/ {print $2}')
  [[ -n "$width" && -n "$height" ]] || continue
  if [[ "$width" != "$height" ]]; then
    echo "警告: 正方形ではありません ($file:t: ${width}x${height})" >&2
  fi
  SOURCES[$width]="$file"
done

if [[ ${#SOURCES[@]} -eq 0 ]]; then
  echo "PNG/JPEG が見つかりません: $SOURCE_DIR" >&2
  exit 1
fi

pick_source_for_size() {
  local target=$1
  if [[ -n "${SOURCES[$target]:-}" ]]; then
    echo "${SOURCES[$target]}"
    return 0
  fi

  local best="" best_size=99999 size
  for size in ${(k)SOURCES}; do
    if (( size >= target && size < best_size )); then
      best="${SOURCES[$size]}"
      best_size=$size
    fi
  done
  if [[ -n "$best" ]]; then
    echo "$best"
    return 0
  fi

  local largest_size=0
  for size in ${(k)SOURCES}; do
    if (( size > largest_size )); then
      best="${SOURCES[$size]}"
      largest_size=$size
    fi
  done
  echo "$best"
}

install_icon() {
  local output_name=$1
  local pixel_size=$2
  local source
  source="$(pick_source_for_size $pixel_size)"
  [[ -n "$source" ]] || { echo "ソースが見つかりません ($output_name)" >&2; exit 1; }

  local current_width
  current_width=$(sips -g pixelWidth "$source" | awk '/pixelWidth/ {print $2}')
  if [[ "$current_width" -eq "$pixel_size" ]]; then
    cp "$source" "$ICONSET/$output_name"
  else
    sips -z "$pixel_size" "$pixel_size" "$source" --out "$ICONSET/$output_name" >/dev/null
  fi
  echo "  $output_name <= ${source:t} (${pixel_size}px)"
}

echo "==> AppIcon を更新します"
echo "    ソース: $SOURCE_DIR"
echo ""

install_icon icon_16x16.png 16
install_icon icon_16x16@2x.png 32
install_icon icon_32x32.png 32
install_icon icon_32x32@2x.png 64
install_icon icon_128x128.png 128
install_icon icon_128x128@2x.png 256
install_icon icon_256x256.png 256
install_icon icon_256x256@2x.png 512
install_icon icon_512x512.png 512
install_icon icon_512x512@2x.png 1024

cp "$ICONSET/icon_512x512@2x.png" "$ICONSET/icon-1024.png"

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

echo ""
echo "✅ AppIcon.appiconset を更新しました"
echo "   Xcode でクリーンビルド（⇧⌘K → ⌘R）すると反映されます。"

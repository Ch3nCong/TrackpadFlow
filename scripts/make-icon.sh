#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
source_icon="$project_dir/Assets/AppIcon-source-v1.png"
iconset_dir="$project_dir/Assets/AppIcon.iconset"
mkdir -p "$iconset_dir"
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" "$source_icon" --out "$iconset_dir/icon_${icon_size}x${icon_size}.png" >/dev/null
  retina_size=$((icon_size * 2))
  sips -z "$retina_size" "$retina_size" "$source_icon" --out "$iconset_dir/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$project_dir/Assets/AppIcon.icns"
print "Created: $project_dir/Assets/AppIcon.icns"

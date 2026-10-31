#!/bin/bash
# Builds the menu bar glyphs from the logo: MenuBarIdle.png (template, adapts to light and dark menu bars)
# and MenuBarRecording.png (red, with a stop square in the lens). Needs ImageMagick. Outputs are committed.
set -euo pipefail
cd "$(dirname "$0")"
S=../icon/source/logo-subject.png
SIZE=36                       # 18 pt at 2x
CROP="880x880+40+41"          # square around the glyph (866x838 at +47+62 in the 960 px subject crop)
LENS="446,606"                # lens centre inside that crop
LENS_EDGE="446,771"           # a point on the lens circle (radius 165)

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# the logo's silhouette, with its opaque near-white lens removed
magick "$S" -alpha extract -threshold 45% "$T/shape.png"
magick "$S" -alpha off -separate -evaluate-sequence min -threshold 72% "$T/lens-raw.png"
magick "$T/lens-raw.png" "$T/shape.png" -compose Multiply -composite "$T/lens.png"
magick "$T/shape.png" "$T/lens.png" -compose Minus_Src -composite -crop "$CROP" +repage "$T/mask.png"

# idle: black glyph, clean round lens hole. macOS recolors a template image for light and dark menu bars.
magick "$T/mask.png" -fill black -draw "circle $LENS $LENS_EDGE" -filter Lanczos -resize "${SIZE}x${SIZE}" "$T/m.png"
magick -size "${SIZE}x${SIZE}" xc:black "$T/m.png" -compose CopyOpacity -composite MenuBarIdle.png

# recording: red glyph, white lens, red stop square in the lens
magick -size 880x880 xc:'#FF3B30' "$T/mask.png" -compose CopyOpacity -composite \
    -fill white -draw "circle $LENS $LENS_EDGE" \
    -fill '#FF3B30' -draw "roundrectangle 366,526 526,686 26,26" \
    -filter Lanczos -resize "${SIZE}x${SIZE}" MenuBarRecording.png
echo "Wrote MenuBarIdle.png and MenuBarRecording.png"

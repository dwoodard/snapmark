#!/bin/bash
# Regenerates packaging/dmg/background.tiff (1x + 2x) with ImageMagick. The output is committed,
# so building a DMG never needs ImageMagick.
set -euo pipefail
cd "$(dirname "$0")"

# 560x340 window. Icons sit at x=150 and x=410, y=170 (see make-dmg.sh).
draw() { # scale output
    local s="$1" out="$2"
    magick -size "$((560 * s))x$((340 * s))" gradient:'#2b2f3a-#14161c' \
        -fill none -stroke '#8a93a6' -strokewidth "$((3 * s))" \
        -draw "line $((222 * s)),$((170 * s)) $((338 * s)),$((170 * s))" \
        -draw "polyline $((318 * s)),$((150 * s)) $((340 * s)),$((170 * s)) $((318 * s)),$((190 * s))" \
        -stroke none -fill '#c7ccd8' -font /System/Library/Fonts/Helvetica.ttc -pointsize "$((15 * s))" -gravity south \
        -annotate "+0+$((34 * s))" 'Drag Snapmark to Applications' \
        -density "$((72 * s))" -units PixelsPerInch "$out"
}
draw 1 bg.png
draw 2 bg@2x.png
tiffutil -cathidpicheck bg.png bg@2x.png -out background.tiff
rm bg.png bg@2x.png
echo "Wrote packaging/dmg/background.tiff"

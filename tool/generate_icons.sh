#!/usr/bin/env bash
# Regenerates the Hobs logo SVGs and every platform launcher icon.
# Needs rsvg-convert (librsvg) and magick (ImageMagick).
set -euo pipefail
cd "$(dirname "$0")/.."

AMBER='#FFAC02'      # the cap
AMBER_DARK='#CC8700' # the cap's band
CREAM='#FBEBC8'      # the pompom
SKIN='#F8C77E'       # face and ears
HAIR='#1E5636'       # the fringe under the cap
INK='#2C2C2A'        # eyes
MOSS='#2F6B4A'       # the tile and splash background, the app's primary color
OUT=assets/logo

# The hob: a little elf with a fringe of dark hair under a pointed cap whose tip
# curls over to a pompom, a darker band round the cap, pointed ears and two
# eyes, on a 100x100 grid. Keep in sync with HobGlyphPainter in
# lib/ui/splash_screen.dart.
CAP="M21 60.5 Q17.6 60.5 17.7 56 C18 44 26 32 37 23 C45 16 54 12.5 62 12.2 C72 12 79 20 81 29 C76 25 69 25 65 27 C62 28.5 62.5 31.5 64.5 33.5 C71 41 77 49 78.6 56 Q79.4 60.5 76 60.5 C66 47 34 47 21 60.5 Z"
GLYPH="<defs><clipPath id=\"cap\"><path d=\"$CAP\"/></clipPath></defs>\
<path d=\"M23 73 C23 52 34 45 50 45 C66 45 77 52 77 73 Z\" fill=\"$HAIR\"/>\
<path d=\"M8.5 57.5 C14 59 21 61 28 63 L29 77 C20 75 12 67 8.5 57.5 Z\" fill=\"$SKIN\"/>\
<path d=\"M91.5 57.5 C86 59 79 61 72 63 L71 77 C80 75 88 67 91.5 57.5 Z\" fill=\"$SKIN\"/>\
<path d=\"M27.5 68 A22.5 22.5 0 0 0 72.5 68 C71 61 63 56.5 53 56.8 C48.5 57 44.8 56.5 43 53.3 C40 58 31 61 27.5 68 Z\" fill=\"$SKIN\"/>\
<path d=\"$CAP\" fill=\"$AMBER\"/>\
<path d=\"M0 46 Q50 33 100 46 L100 100 L0 100 Z\" fill=\"$AMBER_DARK\" clip-path=\"url(#cap)\"/>\
<circle cx=\"83.5\" cy=\"33\" r=\"7\" fill=\"$CREAM\"/>\
<circle cx=\"40\" cy=\"69\" r=\"3.5\" fill=\"$INK\"/>\
<circle cx=\"61\" cy=\"69\" r=\"3.5\" fill=\"$INK\"/>"

svg() { echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">$1</svg>"; }

# Full-bleed square: iOS masks the corners itself.
svg "<rect width=\"100\" height=\"100\" fill=\"$MOSS\"/>$GLYPH" > $OUT/hobs-icon-square.svg
# Rounded: Android legacy launcher, README, web.
svg "<rect width=\"100\" height=\"100\" rx=\"22\" fill=\"$MOSS\"/>$GLYPH" > $OUT/hobs-icon.svg
# macOS: rounded tile inset on a transparent canvas (824/1024, per Apple's grid).
svg "<g transform=\"translate(9.77 9.77) scale(0.8047)\"><rect width=\"100\" height=\"100\" rx=\"22\" fill=\"$MOSS\"/>$GLYPH</g>" > $OUT/hobs-icon-macos.svg
# Bare glyph, no tile.
svg "$GLYPH" > $OUT/hobs-glyph.svg

render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

IOS=ios/Runner/Assets.xcassets/AppIcon.appiconset
for spec in 20:1 20:2 20:3 29:1 29:2 29:3 40:1 40:2 40:3 60:2 60:3 76:1 76:2 83.5:2 1024:1; do
  pt=${spec%:*}; scale=${spec#*:}
  px=$(awk "BEGIN{print $pt*$scale}")
  f="$IOS/Icon-App-${pt}x${pt}@${scale}x.png"
  render $OUT/hobs-icon-square.svg "$px" "$f"
  magick "$f" -background "$MOSS" -alpha remove -alpha off "$f"  # App Store rejects alpha
done

MAC=macos/Runner/Assets.xcassets/AppIcon.appiconset
for px in 16 32 64 128 256 512 1024; do
  render $OUT/hobs-icon-macos.svg $px "$MAC/app_icon_$px.png"
done

for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  render $OUT/hobs-icon.svg "${spec#*:}" "android/app/src/main/res/mipmap-${spec%:*}/ic_launcher.png"
done

# Splash: the bare glyph, 160pt, centered on moss by the native launch screens.
SPLASH=160
LAUNCH=ios/Runner/Assets.xcassets/LaunchImage.imageset
render $OUT/hobs-glyph.svg $SPLASH "$LAUNCH/LaunchImage.png"
render $OUT/hobs-glyph.svg $((SPLASH * 2)) "$LAUNCH/LaunchImage@2x.png"
render $OUT/hobs-glyph.svg $((SPLASH * 3)) "$LAUNCH/LaunchImage@3x.png"
for spec in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  px=$(awk "BEGIN{print $SPLASH*${spec#*:}}")
  render $OUT/hobs-glyph.svg "$px" "android/app/src/main/res/mipmap-${spec%:*}/launch_image.png"
done

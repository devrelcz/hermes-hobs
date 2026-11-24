#!/usr/bin/env bash
# Regenerates the Hobs logo SVGs and every platform launcher icon.
# Needs rsvg-convert (librsvg) and magick (ImageMagick).
set -euo pipefail
cd "$(dirname "$0")/.."

MOSS='#2F6B4A'       # the tile and splash background, the app's primary color
OUT=assets/logo

# The bare glyph matches the HobCrew web mark. Generate the platform variants
# and the bundled Flutter image from this one SVG.
SOURCE="$OUT/hobs-glyph.svg"
GLYPH=$(sed '1d; $d; /<title>/d' "$SOURCE")

svg() { echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">$1</svg>"; }

# Full-bleed square: iOS masks the corners itself.
svg "<rect width=\"100\" height=\"100\" fill=\"$MOSS\"/>$GLYPH" > $OUT/hobs-icon-square.svg
# Rounded: Android legacy launcher, README, web.
svg "<rect width=\"100\" height=\"100\" rx=\"22\" fill=\"$MOSS\"/>$GLYPH" > $OUT/hobs-icon.svg
# macOS: rounded tile inset on a transparent canvas (824/1024, per Apple's grid).
svg "<g transform=\"translate(9.77 9.77) scale(0.8047)\"><rect width=\"100\" height=\"100\" rx=\"22\" fill=\"$MOSS\"/>$GLYPH</g>" > $OUT/hobs-icon-macos.svg
render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

render "$SOURCE" 640 "$OUT/hobs-glyph.png"

IOS=ios/Runner/Assets.xcassets/AppIcon.appiconset
for spec in 20:1 20:2 20:3 29:1 29:2 29:3 40:1 40:2 40:3 60:2 60:3 76:1 76:2 83.5:2 1024:1; do
  pt=${spec%:*}; scale=${spec#*:}
  px=$(awk "BEGIN{print $pt*$scale}")
  f="$IOS/Icon-App-${pt}x${pt}@${scale}x.png"
  render $OUT/hobs-icon-square.svg "$px" "$f"
  magick "$f" -background "$MOSS" -alpha remove -alpha off -strip "$f"  # App Store rejects alpha
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

# Android 8+ adaptive icon: the glyph on a transparent 108dp canvas, kept
# inside the 66dp safe zone, over a moss background layer; and Android 13+
# themed icon: a one-color silhouette the launcher tints to the wallpaper.
# Use the same silhouette and punch out the eyes for a recognizable shape.
ADAPT='transform="translate(18 18) scale(0.72)"'
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 108 108\"><g $ADAPT>$GLYPH</g></svg>" \
  > $OUT/hobs-adaptive-foreground.svg
SILHOUETTE=$(printf '%s\n' "$GLYPH" | sed -e '/<circle/s/fill="[^"]*"/fill="black"/' \
  -e '/<path/s/fill="[^"]*"/fill="white"/')
MONO="<defs><mask id=\"m\"><rect width=\"100\" height=\"100\" fill=\"black\"/>$SILHOUETTE</mask></defs>
<rect width=\"100\" height=\"100\" fill=\"white\" mask=\"url(#m)\"/>"
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 108 108\"><g $ADAPT>$MONO</g></svg>" \
  > $OUT/hobs-adaptive-monochrome.svg
for spec in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  dir="android/app/src/main/res/mipmap-${spec%:*}"
  render $OUT/hobs-adaptive-foreground.svg "${spec#*:}" "$dir/ic_launcher_foreground.png"
  render $OUT/hobs-adaptive-monochrome.svg "${spec#*:}" "$dir/ic_launcher_monochrome.png"
done

# Notification small icon: the same silhouette, full size, white on clear
# (Android draws it in the status bar and tints it).
echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">$MONO</svg>" \
  > $OUT/hobs-notification.svg
for spec in mdpi:24 hdpi:36 xhdpi:48 xxhdpi:72 xxxhdpi:96; do
  dir="android/app/src/main/res/drawable-${spec%:*}"
  mkdir -p "$dir"
  render $OUT/hobs-notification.svg "${spec#*:}" "$dir/ic_notification.png"
done

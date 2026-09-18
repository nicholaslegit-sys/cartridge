#!/bin/sh
# Render v2.html variants to transparent 1024px PNGs with headless Chrome.
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for v in "$@"; do
  "$CH" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size=1024,1024 --virtual-time-budget=3000 \
    --screenshot="$PWD/v3-$v.png" "file://$PWD/v2.html?v=$v" >/dev/null 2>&1
done

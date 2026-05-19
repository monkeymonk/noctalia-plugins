#!/usr/bin/env bash
# Capture a 16:9 @ 960x540 preview.png for the Noctalia plugin registry.
#
# Usage:
#   1. Open the Fingerprint Manager panel in Noctalia.
#   2. Run this script. `slurp` will prompt you to drag a selection over
#      the panel (aim for roughly 16:9 — the script crops + scales the rest).
#
# Requires: grim, slurp, and ImageMagick (`magick` or `convert`).

set -euo pipefail

cd "$(dirname "$0")/.."
out="preview.png"
tmp=$(mktemp --suffix=.png)
trap 'rm -f "$tmp"' EXIT

for cmd in grim slurp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: $cmd not found in PATH" >&2
        exit 1
    fi
done

if command -v magick >/dev/null 2>&1; then
    im=(magick)
elif command -v convert >/dev/null 2>&1; then
    im=(convert)
else
    echo "error: ImageMagick (magick or convert) not found in PATH" >&2
    exit 1
fi

geom=$(slurp)
grim -g "$geom" "$tmp"
"${im[@]}" "$tmp" -resize 960x540^ -gravity center -extent 960x540 "$out"

echo "wrote $out ($(file -b "$out"))"

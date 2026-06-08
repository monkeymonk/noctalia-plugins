#!/usr/bin/env bash
# Capture a 16:9 @ 960x540 preview.png for the Noctalia plugin registry.
#
# Opens the Niri Config panel via IPC, then prompts you (via slurp) to drag a
# selection over it; the captured region is cropped + scaled to the
# registry-mandated dimensions.
#
# Requires: qs, grim, slurp, and ImageMagick (`magick` or `convert`).

set -euo pipefail

cd "$(dirname "$0")/.."
out="preview.png"
tmp=$(mktemp --suffix=.png)
trap 'rm -f "$tmp"' EXIT

for cmd in qs grim slurp; do
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

qs -c noctalia-shell ipc call plugin:niri-config openPanel
sleep 0.3  # let the panel finish rendering before slurp grabs the screen

geom=$(slurp)
grim -g "$geom" "$tmp"
"${im[@]}" "$tmp" -resize 960x540^ -gravity center -extent 960x540 "$out"

echo "wrote $out ($(file -b "$out"))"

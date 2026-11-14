#!/bin/bash
# Development only: ffmpeg is not required to run Undertone.
set -euo pipefail
OUT="${1:-/tmp/undertone-verification}"
mkdir -p "$OUT"
for EXT in wav mp3 m4a flac; do
    ffmpeg -hide_banner -loglevel error -y -f lavfi \
        -i 'sine=frequency=440:duration=2' -ar 44100 -ac 2 "$OUT/tone.$EXT"
done
echo "Fixtures generated in $OUT"

#!/bin/sh

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 <output-directory> [duration-seconds] [interval-seconds]" >&2
    exit 64
fi

output_directory="$1"
duration_seconds="${2:-4}"
interval_seconds="${3:-1}"

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "error: ffmpeg is required" >&2
    exit 69
fi

mkdir -p "$output_directory"

# Peak amplitude 0.003 is approximately -50.5 dBFS. Generate one file and copy it
# so LEFT and RIGHT contain exactly the same samples.
ffmpeg -hide_banner -loglevel error \
    -f lavfi \
    -i "aevalsrc=if(lt(mod(t\,$interval_seconds)\,0.008)\,0.003*sin(2*PI*2000*t)\,0):s=48000:d=$duration_seconds" \
    -ac 1 -c:a pcm_s16le -y "$output_directory/left-click.wav"
cp "$output_directory/left-click.wav" "$output_directory/right-click.wav"

echo "created very quiet (-50.5 dBFS peak) sync files:"
echo "  $output_directory/left-click.wav"
echo "  $output_directory/right-click.wav"

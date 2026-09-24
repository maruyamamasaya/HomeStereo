#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <stereo-input> <output-directory>" >&2
    exit 64
fi

input_path="$1"
output_directory="$2"

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "error: ffmpeg is required" >&2
    exit 69
fi

if [ ! -f "$input_path" ]; then
    echo "error: input file does not exist: $input_path" >&2
    exit 66
fi

mkdir -p "$output_directory"

ffmpeg -hide_banner -loglevel error -i "$input_path" \
    -filter_complex "[0:a]pan=stereo|c0=c0|c1=c0[left];[0:a]pan=stereo|c0=c1|c1=c1[right]" \
    -map "[left]" -c:a pcm_s16le -y "$output_directory/left.wav" \
    -map "[right]" -c:a pcm_s16le -y "$output_directory/right.wav"

echo "created: $output_directory/left.wav"
echo "created: $output_directory/right.wav"

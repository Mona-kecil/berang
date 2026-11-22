#!/bin/sh
# Measures the release targets of #13 on the app's own text cleanup and voice, and prints them as a table.
# usage: bench/release/check.sh [DIR]   Keeps the audio and results in DIR, a new temporary folder by default.
# Needs uv. The first run downloads the alignment model (about 360 MB) and Parakeet (about 2.5 GB).
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$(mktemp -d)}
mkdir -p "$out/hard" "$out/drift"
cd "$here/../../mac"
swift build -c release --product berang-say
say=$(swift build -c release --show-bin-path)/berang-say

python3 "$here/hard.py" "$out/hard.txt"
/usr/bin/time -l "$say" synth "$out/hard.txt" "$out/hard" 2> "$out/hard/time.txt"
uv run "$here/wer.py" "$out/hard"

python3 "$here/../timing/corpus.py" --held-out
/usr/bin/time -l "$say" synth "$here/../timing/held-out.txt" "$out/drift" 2> "$out/drift/time.txt"
"$say" estimate "$out/drift"
uv run "$here/../timing/align.py" "$out/drift"

echo "Results in $out"
python3 "$here/report.py" "$out"

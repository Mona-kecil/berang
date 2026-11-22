#!/bin/sh
# After bench.sh and clean/make_corpus.py: synthesize the cleaned hard text with every model, score raw vs cleaned, rebuild the board.
set -e
cd "$(dirname "$0")"
# Optional: pass a running bench.sh pid to start only after it exits, so timings never overlap.
if [ -n "$1" ]; then while kill -0 "$1" 2>/dev/null; do sleep 20; done; fi
python3 run.py --threads 2 --reps 1 --passages hard_clean --corpus corpus_clean.json --results results_clean
export HF_HOME=$PWD/models/asr/hf CORPUS=corpus_clean.json ASR_OUT=asr_clean.json
envs/asr/bin/python score.py results/*/t2/r0 results_clean/*/t2/r0 2>&1 | grep '^results'
envs/asr/bin/python listen/align.py 2>&1 | grep matched
for d in results_clean/*/t2/r0; do m=$(basename $(dirname $(dirname $d)))
  ffmpeg -loglevel error -y -i $d/hard_clean.wav -ac 1 -c:a aac -b:a 40k listen/${m}_hard_clean.m4a; done
python3 report.py > results/summary.md
python3 listen/build.py

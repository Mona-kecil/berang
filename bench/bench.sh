#!/bin/sh
# Full M1 run. 2 threads is the iPhone 13 proxy, so it gets every passage and 3 interleaved reps.
set -e
cd "$(dirname "$0")"
uptime
python3 run.py --threads 2 --reps 3
python3 run.py --threads 1,4 --reps 1 --passages short,para
uptime
HF_HOME=$PWD/models/asr/hf envs/asr/bin/python score.py results/*/t2/r0 2>&1 | grep '^results'

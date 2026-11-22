#!/bin/sh
# Create one Python env per engine and download every model, so timed runs never include a download.
# Needs: uv, ffmpeg, Apple silicon Mac (the scorer uses MLX). Rerunning skips what exists.
set -e
cd "$(dirname "$0")"
mkenv() { name=$1; shift; [ -d "envs/$name" ] || uv venv -q -p 3.12 "envs/$name"; VIRTUAL_ENV="envs/$name" uv pip install -q "$@"; }

mkenv asr parakeet-mlx jiwer whisper-normalizer
mkenv kitten2_nano kittenml soundfile \
  https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl
mkenv phonon ptts soundfile numpy
mkenv pocket pocket-tts soundfile

# One untimed pass per engine fetches the Hugging Face weights into models/<engine>/hf.
python3 run.py --threads 2 --reps 1 --passages short --results results_setup
HF_HOME="$PWD/models/asr/hf" envs/asr/bin/python -c \
  "from parakeet_mlx import from_pretrained; from_pretrained('mlx-community/parakeet-tdt-0.6b-v2')"
rm -rf results_setup
echo "setup done"

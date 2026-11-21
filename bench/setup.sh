#!/bin/sh
# Create one Python env per engine and download every model, so timed runs never include a download.
# Needs: uv, ffmpeg, git, Apple silicon Mac (the scorer uses MLX). Rerunning skips what exists.
set -e
cd "$(dirname "$0")"
mkenv() { name=$1; shift; [ -d "envs/$name" ] || uv venv -q -p 3.12 "envs/$name"; VIRTUAL_ENV="envs/$name" uv pip install -q "$@"; }
alias_env() { ln -sfn "$2" "envs/$1"; }

mkenv say numpy soundfile
mkenv asr parakeet-mlx jiwer whisper-normalizer
mkenv spk resemblyzer "setuptools<81" soundfile
mkenv kokoro kokoro-onnx soundfile
mkenv piper piper-tts soundfile
mkenv kitten kittenml soundfile \
  https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl
mkenv phonon ptts soundfile numpy
mkenv pocket pocket-tts soundfile
mkenv moss_nano numpy onnxruntime sentencepiece torch torchaudio soundfile huggingface_hub
alias_env kokoro_int8 kokoro
alias_env piper_med piper
alias_env piper_high piper
alias_env kitten08_mini kitten
alias_env kitten2_nano kitten
alias_env kitten2_mini kitten
alias_env pocket_18m pocket

mkdir -p models/kokoro models/piper models/moss_nano
for f in kokoro-v1.0.onnx kokoro-v1.0.int8.onnx voices-v1.0.bin; do
  [ -f "models/kokoro/$f" ] || curl -sfL -o "models/kokoro/$f" \
    "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/$f"
done
(cd models/piper && ../../envs/piper/bin/python -m piper.download_voices en_US-lessac-medium en_US-lessac-high)
[ -d models/moss_nano/src ] || git clone -q --depth 1 https://github.com/OpenMOSS/MOSS-TTS-Nano models/moss_nano/src
(cd models/moss_nano/src && ../../../envs/moss_nano/bin/python -c \
  "import sys; sys.path.insert(0, '.'); from onnx_tts_runtime import OnnxTtsRuntime; OnnxTtsRuntime(model_dir=None)")

# One untimed pass per engine fetches the Hugging Face weights into models/<engine>/hf.
python3 run.py --threads 2 --reps 1 --passages short --results results_setup
HF_HOME="$PWD/models/asr/hf" envs/asr/bin/python -c \
  "from parakeet_mlx import from_pretrained; from_pretrained('mlx-community/parakeet-tdt-0.6b-v2')"
rm -rf results_setup
echo "setup done"

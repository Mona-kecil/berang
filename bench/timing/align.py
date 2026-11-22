# /// script
# requires-python = "==3.12.*"
# dependencies = ["torch==2.5.1", "torchaudio==2.5.1"]
# ///
"""Reference word starts for each chunk in DIR, by forced alignment of the chunk's text to its audio.

Run: uv run bench/timing/align.py DIR   Writes DIR/reference.json: {wav: [[word, start seconds], ...]}.
Uses torchaudio's wav2vec2 base (960 h LibriSpeech) English CTC model, downloaded on first run (360 MB).
"""
import json
import os
import re
import sys
import wave as wavfile

import torch
import torchaudio

d = sys.argv[1]
bundle = torchaudio.pipelines.WAV2VEC2_ASR_BASE_960H
model = bundle.get_model().eval()
labels = bundle.get_labels()  # ('-', '|', 'E', 'T', ...): blank, word separator, letters, apostrophe
index = {c: i for i, c in enumerate(labels)}

out = {}
for entry in json.load(open(os.path.join(d, "manifest.json"))):
    words = entry["text"].split()
    # Each word as the model's letters; a word with none (like "&") is left out of the alignment.
    spelled = [re.sub(r"[^A-Z']", "", w.upper()) for w in words]
    kept = [i for i, s in enumerate(spelled) if s]
    with wavfile.open(os.path.join(d, entry["wav"])) as f:  # berang-say writes 16-bit mono PCM
        rate = f.getframerate()
        pcm = torch.frombuffer(bytearray(f.readframes(f.getnframes())), dtype=torch.int16)
    wave = (pcm.float() / 32767).unsqueeze(0)
    wave = torchaudio.functional.resample(wave, rate, bundle.sample_rate)
    with torch.inference_mode():
        emission, _ = model(wave)
    emission = torch.log_softmax(emission, dim=-1)
    tokens = [index[c] for i in kept for c in spelled[i]]
    aligned, _ = torchaudio.functional.forced_align(emission, torch.tensor([tokens]), blank=0)
    spans = torchaudio.functional.merge_tokens(aligned[0], torch.zeros(len(aligned[0])))
    seconds = wave.shape[1] / bundle.sample_rate / emission.shape[1]
    starts, at = [], 0
    for i in kept:
        starts.append([words[i], spans[at].start * seconds])
        at += len(spelled[i])
    out[entry["wav"]] = starts
json.dump(out, open(os.path.join(d, "reference.json"), "w"))
print(f"{len(out)} chunks aligned")

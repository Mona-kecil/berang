"""Read the paragraph and the cleaned hard text in a cloned voice. usage: run_clone.py <ref.wav>"""
import json
import os
import sys
import time

import numpy as np
import soundfile as sf
import torch
from pocket_tts import TTSModel

HERE = os.path.dirname(os.path.abspath(__file__))
model, ref = "pocket", sys.argv[1]
torch.set_num_threads(2)
tts = TTSModel.load_model()

t = time.perf_counter()
state = tts.get_state_for_audio_prompt(ref)
print(f"{model}: voice prompt from {sf.info(ref).duration:.1f}s clip took {time.perf_counter() - t:.2f}s")

corpus = json.load(open(f"{HERE}/../corpus.json"))
clean = json.load(open(f"{HERE}/../corpus_clean.json"))
texts = {"para": next(p for p in corpus["passages"] if p["id"] == "para")["sentences"],
         "hard": next(p for p in corpus["passages"] if p["id"] == "hard")["sentences"],
         "hard_clean": next(p for p in clean["passages"] if p["id"] == "hard_clean")["sentences"]}
os.makedirs(f"{HERE}/{model}", exist_ok=True)
metrics = {}
for pid, sents in texts.items():
    t, first, parts = time.perf_counter(), None, []
    for s in sents:
        for c in tts.generate_audio_stream(state, s):
            first = first or time.perf_counter() - t
            parts.append(c.detach().float().numpy())
    audio = np.concatenate(parts)
    sf.write(f"{HERE}/{model}/{pid}.wav", audio, tts.sample_rate)
    took = time.perf_counter() - t
    metrics[pid] = {"first_audio_s": first, "rtf": took / (len(audio) / tts.sample_rate)}
    print(f"{model} {pid}: {len(audio) / tts.sample_rate:.1f}s audio, first audio {first:.2f}s, gen {took / (len(audio) / tts.sample_rate):.2f}x")
json.dump(metrics, open(f"{HERE}/{model}/metrics.json", "w"))

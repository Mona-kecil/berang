"""Transcribe each run's wavs with Parakeet and score word error rate against what a careful reader would say.

usage: envs/asr/bin/python score.py results/<model>/t<threads>/r<rep> [...]
Writes asr.json next to metrics.json.
"""
import json
import os
import re
import sys

import jiwer
from parakeet_mlx import from_pretrained
from whisper_normalizer.english import EnglishTextNormalizer

_whisper = EnglishTextNormalizer()
_CANON = [
    (r"\b(\d+) (\d{2})\b", r"\1\2"),   # 10 45 -> 1045
    (r"\b([ap]) m\b", r"\1m"),          # a m -> am
    (r"\b(\d+)(st|nd|rd|th)\b", r"\1"),  # 22nd -> 22
    (r"\be g\b", "for example"),
    (r"\bstand up\b", "standup"),
    (r"\bhttps?\b", ""),                 # reading the scheme aloud is fine either way
    (r"\s+", " "),
]


def norm(text):
    out = _whisper(text)
    for pat, rep in _CANON:
        out = re.sub(pat, rep, out)
    return out.strip()
corpus = json.load(open(os.path.join(os.path.dirname(__file__), os.environ.get("CORPUS", "corpus.json"))))
refs = {p["id"]: " ".join(p.get("spoken", p["sentences"])) for p in corpus["passages"]}
model = from_pretrained("mlx-community/parakeet-tdt-0.6b-v2")

for run_dir in sys.argv[1:]:
    out = {}
    for pid, ref in refs.items():
        wav = os.path.join(run_dir, f"{pid}.wav")
        if not os.path.exists(wav):
            continue
        hyp = model.transcribe(wav).text
        r, h = norm(ref), norm(hyp)
        m = jiwer.process_words(r, h)
        out[pid] = {"wer": m.wer, "subs": m.substitutions, "dels": m.deletions,
                    "ins": m.insertions, "ref_words": len(r.split()), "hyp": hyp}
    json.dump(out, open(os.path.join(run_dir, os.environ.get("ASR_OUT", "asr.json")), "w"), indent=1)
    print(run_dir, {k: round(v["wer"], 3) for k, v in out.items()})

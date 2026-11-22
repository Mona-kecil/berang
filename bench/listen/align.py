"""Word timings for each listening clip: Parakeet word times matched onto the original text's words.

Unmatched text words (skipped, garbled, or written differently like $3.5M) get times interpolated
from their matched neighbours. Writes listen/timings.json: {model: {passage: [[start, end], ...]}}.
"""
import difflib
import glob
import json
import os
import re

from parakeet_mlx import from_pretrained

HERE = os.path.dirname(os.path.abspath(__file__))
corpus = json.load(open(f"{HERE}/../corpus.json"))
texts = {p["id"]: " ".join(p["sentences"]).split() for p in corpus["passages"] if p["id"] in ("para", "hard")}
asr = from_pretrained("mlx-community/parakeet-tdt-0.6b-v2")


def key(w):
    return re.sub(r"[^a-z0-9]", "", w.lower())


def asr_words(wav):
    words = []
    for s in asr.transcribe(wav).sentences:
        for t in s.tokens:
            if t.text.startswith(" ") or not words:
                words.append([t.text.strip(), t.start, t.end])
            else:
                words[-1][0] += t.text
                words[-1][2] = t.end
    return words


def align(ref, hyp, total):
    times = [None] * len(ref)
    sm = difflib.SequenceMatcher(a=[key(w) for w in ref], b=[key(w[0]) for w in hyp], autojunk=False)
    for blk in sm.get_matching_blocks():
        for i in range(blk.size):
            times[blk.a + i] = [hyp[blk.b + i][1], hyp[blk.b + i][2]]
    known = [i for i, t in enumerate(times) if t]
    for i, t in enumerate(times):
        if t:
            continue
        prev = max((k for k in known if k < i), default=None)
        nxt = min((k for k in known if k > i), default=None)
        lo, lo_i = (times[prev][1], prev) if prev is not None else (0.0, -1)
        hi, hi_i = (times[nxt][0], nxt) if nxt is not None else (total, len(ref))
        step = (hi - lo) / (hi_i - lo_i)
        times[i] = [lo + step * (i - lo_i - 1), lo + step * (i - lo_i)]
    return [[round(a, 3), round(b, 3)] for a, b in times], len(known) / len(ref)


import soundfile as sf

out = {}
CLONES = {k: v for k, v in {"pocket_you": f"{HERE}/../clone/pocket"}.items()
          if os.path.exists(f"{v}/para.wav")}
for model, d in [(d.split("/results/")[1].split("/")[0], d) for d in sorted(glob.glob(f"{HERE}/../results/*/t2/r0"))] + list(CLONES.items()):
    for pid, ref in texts.items():
        wav = f"{d}/{pid}.wav"
        info = sf.info(wav)
        times, matched = align(ref, asr_words(wav), info.frames / info.samplerate)
        out.setdefault(model, {})[pid] = times
        print(model, pid, f"{matched:.0%} of words matched")

import sys
sys.path.insert(0, f"{HERE}/../clean")
from clean import prepare

hard_src = " ".join(next(p for p in corpus["passages"] if p["id"] == "hard")["sentences"])
prep = prepare(hard_src)
char_src = []  # spoken char -> (src_start, src_end)
for seg in prep.segments:
    for i in range(len(seg.spoken)):
        char_src.append((seg.src_start + i, seg.src_start + i + 1) if seg.kind == "text" else (seg.src_start, seg.src_end))
spoken_words = [(m.group(0), char_src[m.start()][0], char_src[m.end() - 1][1]) for m in re.finditer(r"\S+", prep.spoken)]
assert [w for w, *_ in spoken_words] == " ".join(c.text for c in prep.chunks).split(), "chunk text drifted from segments"
display = [(m.start(), m.end()) for m in re.finditer(r"\S+", hard_src)]
assert len(display) == len(texts["hard"])

for model, d in [(d.split("/results_clean/")[1].split("/")[0], d) for d in sorted(glob.glob(f"{HERE}/../results_clean/*/t2/r0"))] + list(CLONES.items()):
    wav = f"{d}/hard_clean.wav"
    info = sf.info(wav)
    times, matched = align([w for w, *_ in spoken_words], asr_words(wav), info.frames / info.samplerate)
    shown = []
    for ds, de in display:
        hit = [t for (w, ss, se), t in zip(spoken_words, times) if ss < de and se > ds]
        shown.append([min(t[0] for t in hit), max(t[1] for t in hit)] if hit else None)
    for i, t in enumerate(shown):  # words with no spoken counterpart: zero-length at the previous word's end
        if t is None:
            prev = next((shown[j] for j in range(i - 1, -1, -1) if shown[j]), [0, 0])
            shown[i] = [prev[1], prev[1]]
    out.setdefault(model, {})["hard_clean"] = shown
    print(model, "hard_clean", f"{matched:.0%} of spoken words matched")

json.dump(out, open(f"{HERE}/timings.json", "w"))

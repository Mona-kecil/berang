# /// script
# requires-python = "==3.12.*"
# dependencies = ["parakeet-mlx==0.7.0", "jiwer==4.0.0", "whisper-normalizer==0.1.15"]
# ///
"""Word error rate of the voice on hard text: Parakeet transcribes each paragraph's chunks, scored against what a
careful reader would say.

Run: uv run bench/release/wer.py DIR   DIR is from berang-say synth of hard.py's text. Writes DIR/wer.json.
"""
import json
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, "..")]
import jiwer
from hard import cases
from parakeet_mlx import from_pretrained
from score import MODEL, norm

d = sys.argv[1]
paragraphs = defaultdict(list)
for e in json.load(open(os.path.join(d, "manifest.json"))):
    paragraphs[int(e["wav"][1:].split("c")[0])].append(e["wav"])
model = from_pretrained(MODEL)
out, errors, words = [], 0, 0
for p, case in enumerate(cases()):
    heard = " ".join(model.transcribe(os.path.join(d, w)).text for w in paragraphs[p])
    m = jiwer.process_words(norm(case["out"]), norm(heard))
    errors += m.substitutions + m.deletions + m.insertions
    words += len(norm(case["out"]).split())
    out.append({"said": case["out"], "heard": heard, "errors": m.substitutions + m.deletions + m.insertions})
json.dump({"wer": errors / words, "words": words, "paragraphs": out}, open(os.path.join(d, "wer.json"), "w"), indent=1)
print(f"WER {errors / words:.1%} over {words} words")

"""Input text -> what the voice should be given. Run: python3 bench/clean/test_clean.py

The cases live in cases.json, which the Swift port's tests read too.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from clean import prepare

cases = json.load(open(os.path.join(HERE, "cases.json")))
fails = 0
for c in cases["text"]:
    got = " ".join(ch.text for ch in prepare(c["in"]).chunks)
    if got != c["out"]:
        fails += 1
        print(f"FAIL\n  in:   {c['in']!r}\n  want: {c['out']!r}\n  got:  {got!r}")
for c in cases["chunks"]:
    got = [ch.text for ch in prepare(c["in"]).chunks]
    if got != c["out"]:
        fails += 1
        print(f"FAIL chunks\n  in:   {c['in']!r}\n  want: {c['out']!r}\n  got:  {got!r}")

# Highlight mapping: every chunk's source span must cover the source text it was made from.
src = cases["spans"]["in"]
got = [[ch.text, src[ch.src_start:ch.src_end]] for ch in prepare(src).chunks]
if got != cases["spans"]["out"]:
    fails += 1
    print(f"FAIL spans\n  want: {cases['spans']['out']}\n  got:  {got}")

total = len(cases["text"]) + len(cases["chunks"]) + 1
print(f"{total - fails}/{total} passed")
sys.exit(1 if fails else 0)

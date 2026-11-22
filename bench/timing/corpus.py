"""Writes corpus.txt: paragraphs to measure word timing on, from the saved pages and the cleanup cases.

The estimator's weights were fitted on corpus.txt. With --held-out, writes held-out.txt instead: paragraphs
from two pages the fit never saw, to check that the fit carries over.

Run: python3 bench/timing/corpus.py [--held-out]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(HERE, "../../mac/Tests/TextGrabTests/Pages")
PAGE_NAMES = ["wikipedia-otter", "wikipedia-photosynthesis", "wikipedia-ada-lovelace", "wikipedia-apollo-11",
              "wikipedia-coffee", "wikipedia-speech-synthesis", "wikipedia-solar-system", "wikivoyage-jakarta",
              "wikibooks-cookbook-pancake", "simple-wikipedia-otter"]

HELD_OUT = ["wikipedia-python", "wikipedia-jakarta"]
held_out = "--held-out" in sys.argv


def prose(name):
    blocks = open(os.path.join(PAGES, name + ".md"), encoding="utf-8").read().split("\n\n")
    return [b for b in blocks if not b.startswith("# ") and 150 <= len(b) <= 700]


paragraphs = []
if held_out:
    for name in HELD_OUT:
        paragraphs += prose(name)[2:9]
else:
    for name in PAGE_NAMES:
        paragraphs += prose(name)[1:4]
    cases = json.load(open(os.path.join(HERE, "../clean/cases.json"), encoding="utf-8"))
    paragraphs += [c["in"] for c in cases["text"] if len(c["in"].split()) >= 6]

with open(os.path.join(HERE, "held-out.txt" if held_out else "corpus.txt"), "w", encoding="utf-8") as f:
    f.write("\n\n".join(p.replace("\n", " ") for p in paragraphs) + "\n")
print(f"{len(paragraphs)} paragraphs")

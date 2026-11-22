"""Compares Berang's estimated word starts with forced-aligned word starts on the same audio.

Run, from mac/:
  swift run -c release berang-say synth ../bench/timing/corpus.txt DIR
  swift run -c release berang-say estimate DIR
  uv run ../bench/timing/align.py DIR      # once per synth; writes DIR/reference.json
  python3 ../bench/timing/compare.py DIR
"""
import difflib
import json
import os
import re
import statistics
import sys

d = sys.argv[1]
norm = lambda w: re.sub(r"[^a-z']", "", w.lower())
references = json.load(open(os.path.join(d, "reference.json")))


def reference(wav):
    return [(norm(w), t) for w, t in references[wav]]


def errors(starts_of):
    """Signed errors (estimate minus reference) over all words both sides agree on."""
    out = []
    for e in estimates:
        ref = reference(e["wav"])
        ours = [norm(w) for w in e["words"]]
        starts = starts_of(e)
        sm = difflib.SequenceMatcher(None, ours, [w for w, _ in ref], autojunk=False)
        for a, b, n in sm.get_matching_blocks():
            out += [starts[a + k] - ref[b + k][1] for k in range(n)]
    return out


def report(name, errs):
    a = sorted(abs(x) for x in errs)
    within = sum(x <= 0.15 for x in a) / len(a)
    print(f"{name:28} words {len(a):5}  median {statistics.median(a)*1000:4.0f} ms  p90 {a[int(len(a)*0.9)]*1000:4.0f} ms"
          f"  within 150 ms {within:5.1%}  bias {statistics.mean(errs)*1000:+4.0f} ms")


def by_characters(e):
    """Baseline: the chunk's whole length spread by characters."""
    lengths = [len(w) + 1 for w in e["words"]]
    total, t, out = sum(lengths), 0, []
    for n in lengths:
        out.append(e["seconds"] * t / total)
        t += n
    return out


estimates = json.load(open(os.path.join(d, "estimates.json")))
report("spread by characters", errors(by_characters))
report("berang estimate", errors(lambda e: e["starts"]))

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

norm = lambda w: re.sub(r"[^a-z']", "", w.lower())


def errors(d, starts_of):
    """Signed errors (estimate minus reference) over all words both sides agree on, in DIR d."""
    references = json.load(open(os.path.join(d, "reference.json")))
    out = []
    for e in json.load(open(os.path.join(d, "estimates.json"))):
        ref = [(norm(w), t) for w, t in references[e["wav"]]]
        ours = [norm(w) for w in e["words"]]
        starts = starts_of(e)
        sm = difflib.SequenceMatcher(None, ours, [w for w, _ in ref], autojunk=False)
        for a, b, n in sm.get_matching_blocks():
            out += [starts[a + k] - ref[b + k][1] for k in range(n)]
    return out


def summary(errs):
    a = sorted(abs(x) for x in errs)
    return {"words": len(a), "median": statistics.median(a), "p90": a[int(len(a) * 0.9)],
            "within150": sum(x <= 0.15 for x in a) / len(a), "bias": statistics.mean(errs)}


def by_characters(e):
    """Baseline: the chunk's whole length spread by characters."""
    lengths = [len(w) + 1 for w in e["words"]]
    total, t, out = sum(lengths), 0, []
    for n in lengths:
        out.append(e["seconds"] * t / total)
        t += n
    return out


if __name__ == "__main__":
    for name, starts_of in [("spread by characters", by_characters), ("berang estimate", lambda e: e["starts"])]:
        s = summary(errors(sys.argv[1], starts_of))
        print(f"{name:28} words {s['words']:5}  median {s['median']*1000:4.0f} ms  p90 {s['p90']*1000:4.0f} ms"
              f"  within 150 ms {s['within150']:5.1%}  bias {s['bias']*1000:+4.0f} ms")

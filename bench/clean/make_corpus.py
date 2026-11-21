"""corpus_clean.json: the hard passage raw and through clean.py, scored against one reference.

The reference is how a careful reader would say it, with the URL as "link to example dot com"
(the reading we chose), so raw and cleaned audio are judged on the same target.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from clean import prepare

c = json.load(open(f"{HERE}/../corpus.json"))
hard = next(p for p in c["passages"] if p["id"] == "hard")
spoken = list(hard["spoken"])
spoken[2] = "Download version two point one point four from link to example dot com before Friday."
chunks = [ch.text for ch in prepare(" ".join(hard["sentences"])).chunks]
json.dump({"warmup": c["warmup"], "passages": [
    {"id": "hard", "sentences": hard["sentences"], "spoken": spoken},
    {"id": "hard_clean", "sentences": chunks, "spoken": spoken},
]}, open(f"{HERE}/../corpus_clean.json", "w"), indent=1)
print("\n".join(chunks))

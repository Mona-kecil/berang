"""Hard text: the cleanup cases of six or more words, with what a careful reader would say for each.

Run: python3 bench/release/hard.py FILE   Writes the cases' text to FILE, one paragraph per case.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def cases():
    text = json.load(open(os.path.join(HERE, "../clean/cases.json"), encoding="utf-8"))["text"]
    return [c for c in text if len(c["in"].split()) >= 6]


if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        f.write("\n\n".join(c["in"] for c in cases()) + "\n")

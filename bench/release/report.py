"""Prints the release targets of #13 as a Markdown table, from the runs check.sh made in DIR.

Run: python3 bench/release/report.py DIR
"""
import json
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "../timing"))
from compare import errors, summary

d = sys.argv[1]
first = json.load(open(os.path.join(d, "hard/first-word.json"))) + json.load(open(os.path.join(d, "drift/first-word.json")))
wer = json.load(open(os.path.join(d, "hard/wer.json")))
drift = summary(errors(os.path.join(d, "drift"), lambda e: e["starts"]))
peak = max(int(re.search(r"(\d+)\s+maximum resident set size", open(os.path.join(d, run, "time.txt")).read()).group(1))
           for run in ["hard", "drift"]) / 2**20

rows = [
    ("Time to first word", f"median {statistics.median(first)*1000:.0f} ms, max {max(first)*1000:.0f} ms, "
     f"{len(first)} paragraphs", statistics.median(first) < 0.3, "under 300 ms"),
    ("Word errors on hard text", f"{wer['wer']:.1%} of {wer['words']} words", wer["wer"] < 0.03, "under 3%"),
    ("Highlight drift", f"median {drift['median']*1000:.0f} ms, p90 {drift['p90']*1000:.0f} ms, "
     f"{drift['within150']:.0%} of {drift['words']} words within 150 ms", drift["median"] < 0.15, "under 150 ms"),
    ("Peak memory", f"{peak:.0f} MB", peak < 300, "under 300 MB"),
]
print("| Target | Goal | Measured | Met |\n|---|---|---|---|")
for name, measured, met, goal in rows:
    print(f"| {name} | {goal} | {measured} | {'yes' if met else 'no'} |")

"""Run every adapter at each thread count, interleaving models across reps. Skips runs that already finished.

usage: python3 run.py [--models a,b] [--threads 1,2,4] [--reps 3] [--passages all]
"""
import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
p = argparse.ArgumentParser()
p.add_argument("--models", default=",".join(sorted(
    f[:-3] for f in os.listdir(f"{ROOT}/adapters") if f.endswith(".py") and f != "common.py")))
p.add_argument("--threads", default="1,2,4")
p.add_argument("--reps", type=int, default=3)
p.add_argument("--passages", default="all")
p.add_argument("--corpus", default="corpus.json")
p.add_argument("--results", default="results")
a = p.parse_args()
models = a.models.split(",")
threads = [int(t) for t in a.threads.split(",")]

for rep in range(a.reps):
    order = models[rep % len(models):] + models[:rep % len(models)]
    for m in order:
        for t in threads:
            out = f"{ROOT}/{a.results}/{m}/t{t}/r{rep}"
            if os.path.exists(f"{out}/metrics.json"):
                continue
            n = str(t)
            env = dict(os.environ, OMP_NUM_THREADS=n, MKL_NUM_THREADS=n, OPENBLAS_NUM_THREADS=n,
                       VECLIB_MAXIMUM_THREADS=n, RAYON_NUM_THREADS=n, TOKENIZERS_PARALLELISM="false",
                       HF_HOME=f"{ROOT}/models/{m}/hf", HF_HUB_DISABLE_TELEMETRY="1")
            cmd = ["/usr/bin/time", "-l", f"{ROOT}/envs/{m}/bin/python", f"{ROOT}/adapters/{m}.py",
                   "--corpus", f"{ROOT}/{a.corpus}", "--out", out, "--threads", n, "--passages", a.passages]
            r = subprocess.run(cmd, env=env, capture_output=True, text=True)
            rss = re.search(r"(\d+)\s+maximum resident set size", r.stderr)
            row = {"model": m, "threads": t, "rep": rep, "ok": r.returncode == 0,
                   "peak_rss_mb": int(rss.group(1)) / 2**20 if rss else None}
            if r.returncode:
                row["error"] = r.stderr[-1500:]
            else:
                json.dump(row, open(f"{out}/rss.json", "w"))
            os.makedirs(f"{ROOT}/{a.results}", exist_ok=True)
            with open(f"{ROOT}/{a.results}/runs.jsonl", "a") as f:
                f.write(json.dumps(row) + "\n")
            print(m, t, rep, "ok" if row["ok"] else "FAIL", row["peak_rss_mb"], file=sys.stderr, flush=True)

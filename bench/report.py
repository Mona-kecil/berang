"""Aggregate results/ into results/summary.json and a markdown table on stdout."""
import glob
import json
import os
import statistics as st

ROOT = os.path.dirname(os.path.abspath(__file__))
M = f"{ROOT}/models"
FILES = {
    "kokoro": [f"{M}/kokoro/kokoro-v1.0.onnx", f"{M}/kokoro/voices-v1.0.bin"],
    "kokoro_int8": [f"{M}/kokoro/kokoro-v1.0.int8.onnx", f"{M}/kokoro/voices-v1.0.bin"],
    "piper_med": [f"{M}/piper/en_US-lessac-medium.onnx"],
    "piper_high": [f"{M}/piper/en_US-lessac-high.onnx"],
    "moss_nano": [f"{M}/moss_nano/src/models"],
    "say": [],
}


def size_mb(model):
    """Model files the voice needs: explicit files, or the Hugging Face snapshot (each file once)."""
    paths = FILES.get(model)
    if paths is None:
        paths = glob.glob(f"{M}/{model}/hf/hub/*/snapshots/*")
    total = 0
    for p in paths:
        if os.path.isfile(p):
            total += os.path.getsize(p)
        for d, _, fs in os.walk(p):
            total += sum(os.path.getsize(os.path.realpath(os.path.join(d, f))) for f in fs)
    return total / 2**20


def load(path):
    return json.load(open(path)) if os.path.exists(path) else None


def stat(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    return {"median": st.median(vals), "min": min(vals), "max": max(vals), "n": len(vals)}


def passage(metrics, pid):
    return next((p for p in metrics["passages"] if p["id"] == pid), None)


summary = {}
for mdir in sorted(glob.glob(f"{ROOT}/results/*/")):
    model = os.path.basename(mdir.rstrip("/"))
    runs = {}
    for rdir in glob.glob(f"{mdir}t*/r*/"):
        t = int(rdir.split("/t")[-1].split("/")[0])
        met, rss = load(f"{rdir}metrics.json"), load(f"{rdir}rss.json")
        if met:
            runs.setdefault(t, []).append((met, rss, load(f"{rdir}asr.json"), rdir))
    if 2 not in runs:
        continue
    t2 = runs[2]
    s = {
        "info": t2[0][0]["info"],
        "size_mb": size_mb(model),
        "peak_rss_mb": stat([r and r["peak_rss_mb"] for _, r, _, _ in t2]),
        "load_s": stat([m["load_s"] for m, *_ in t2]),
        "cold_first_s": stat([m["cold_first_s"] for m, *_ in t2]),
        "first_audio_short_s": stat([passage(m, "short")["first_audio_s"] for m, *_ in t2]),
        "first_audio_para_s": stat([passage(m, "para")["first_audio_s"] for m, *_ in t2]),
        "rtf_long": stat([passage(m, "long")["rtf"] for m, *_ in t2]),
        "stall_long_s": stat([passage(m, "long")["stall_s"] for m, *_ in t2]),
        "empty_sentences": sum(p["empty_sentences"] for m, *_ in t2 for p in m["passages"]),
        "rtf_para_by_threads": {t: stat([passage(m, "para")["rtf"] for m, *_ in rs]) for t, rs in sorted(runs.items())},
        "wer": next(({k: v["wer"] for k, v in a.items()} for _, _, a, _ in sorted(t2, key=lambda x: x[3]) if a), None),
        "audio_dir": sorted(r for *_, r in t2)[0],
    }
    summary[model] = s

json.dump(summary, open(f"{ROOT}/results/summary.json", "w"), indent=1)


def f(x, d=2):
    return "–" if x is None else f"{x['median']:.{d}f}" + (f" ({x['min']:.{d}f}–{x['max']:.{d}f})" if x["n"] > 1 else "")


print("| model | size MB | peak RAM MB | first audio s | speed (RTF, long) | stalls s (long) | RTF 1/2/4 thr | WER para | WER hard | WER long |")
print("|---|---|---|---|---|---|---|---|---|---|")
for model, s in sorted(summary.items(), key=lambda kv: kv[1]["rtf_long"]["median"] if kv[1]["rtf_long"] else 9):
    thr = "/".join(f"{s['rtf_para_by_threads'][t]['median']:.2f}" if t in s["rtf_para_by_threads"] else "–" for t in (1, 2, 4))
    w = s["wer"] or {}
    print(f"| {model} | {s['size_mb']:.0f} | {f(s['peak_rss_mb'], 0)} | {f(s['first_audio_short_s'])} | {f(s['rtf_long'])} | "
          f"{f(s['stall_long_s'], 1)} | {thr} | " + " | ".join(f"{100 * w[k]:.1f}%" if k in w else "–" for k in ("para", "hard", "long")) + " |")

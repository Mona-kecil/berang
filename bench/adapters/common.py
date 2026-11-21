"""Shared timing loop. Each adapter supplies load(threads) -> engine with .sr, .info and .synth(text) -> iterable of float32 chunks.

Text goes in one sentence at a time, the way a reader app would stream it.
Playback is simulated: it starts when the first chunk exists, and each later
sentence stalls playback if it is not ready when the previous one ends.
"""
import argparse
import json
import os
import time

import numpy as np
import soundfile as sf


def _collect(chunks):
    parts = [np.asarray(c, dtype=np.float32).reshape(-1) for c in chunks]
    return np.concatenate(parts) if parts else np.zeros(0, np.float32)


def run(load):
    p = argparse.ArgumentParser()
    p.add_argument("--corpus", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--threads", type=int, required=True)
    p.add_argument("--passages", default="all")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    corpus = json.load(open(a.corpus))

    t = time.perf_counter()
    engine = load(a.threads)
    load_s = time.perf_counter() - t

    t = time.perf_counter()
    warm = _collect(engine.synth(corpus["warmup"]))
    cold_s = time.perf_counter() - t
    if warm.size == 0:
        raise SystemExit("warmup produced no audio")

    wanted = None if a.passages == "all" else set(a.passages.split(","))
    passages = []
    for psg in corpus["passages"]:
        if wanted and psg["id"] not in wanted:
            continue
        audios, sents, first = [], [], None
        t0 = time.perf_counter()
        for s in psg["sentences"]:
            parts = []
            for c in engine.synth(s):
                c = np.asarray(c, dtype=np.float32).reshape(-1)
                if first is None and c.size:
                    first = time.perf_counter() - t0
                parts.append(c)
            audio = np.concatenate(parts) if parts else np.zeros(0, np.float32)
            sents.append({"ready_s": time.perf_counter() - t0, "audio_s": audio.size / engine.sr})
            audios.append(audio)
        synth_s = time.perf_counter() - t0
        audio = np.concatenate(audios)
        audio_s = audio.size / engine.sr

        clock = max(first + sents[0]["audio_s"], sents[0]["ready_s"])
        stall = 0.0
        for s in sents[1:]:
            stall += max(0.0, s["ready_s"] - clock)
            clock = max(clock, s["ready_s"]) + s["audio_s"]

        sf.write(os.path.join(a.out, f"{psg['id']}.wav"), audio, engine.sr)
        passages.append({
            "id": psg["id"],
            "first_audio_s": first,
            "synth_s": synth_s,
            "audio_s": audio_s,
            "rtf": synth_s / audio_s if audio_s else None,
            "stall_s": stall,
            "empty_sentences": sum(1 for s in sents if s["audio_s"] < 0.2),
        })

    json.dump({
        "threads": a.threads,
        "load_s": load_s,
        "cold_first_s": cold_s,
        "sr": engine.sr,
        "info": engine.info,
        "passages": passages,
    }, open(os.path.join(a.out, "metrics.json"), "w"), indent=1)

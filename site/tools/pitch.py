# Per voice: each sentence's median pitch (semitones from the voice's own median) and loudness (dB), and the spread.
# A voice whose sentences sound like one reading keeps both spreads small.
import json, math, os, subprocess, sys, tempfile, wave, array, statistics as st
folder = sys.argv[1]
t = json.load(open(f"{folder}/timing.json"))
firsts = [i for i in range(len(t["say"])) if i == 0 or t["say"][i - 1][-1] in ".!?"]
def pitch(frame, rate):
    e = sum(x * x for x in frame)
    if e < 1e-3 * len(frame): return None, e
    best, lag_best = 0, 0
    for lag in range(rate // 400, rate // 70):
        c = sum(frame[i] * frame[i + lag] for i in range(0, len(frame) - lag, 2))
        if c > best: best, lag_best = c, lag
    return (rate / lag_best if lag_best and best > 0.3 * e / 2 else None), e
rows = []
for voice, starts in sorted(t["voices"].items()):
    wav = tempfile.mktemp(suffix=".wav")
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@8000", "-c", "1", f"{folder}/{voice}.m4a", wav], check=True)
    w = wave.open(wav); rate = w.getframerate(); a = array.array("h", w.readframes(w.getnframes())); os.remove(wav)
    x = [v / 32768 for v in a]; n = int(.04 * rate)
    bounds = [starts[i] for i in firsts] + [len(x) / rate]
    sents = []
    for s0, s1 in zip(bounds, bounds[1:]):
        f0s, es = [], []
        for k in range(int(s0 * rate), int(s1 * rate) - n, n):
            f, e = pitch(x[k:k + n], rate)
            if f: f0s.append(f); es.append(e / n)
        sents.append((st.median(f0s), 10 * math.log10(st.mean(es))))
    ref = st.median(f for f, _ in sents)
    semis = [12 * math.log2(f / ref) for f, _ in sents]; dbs = [d for _, d in sents]
    rows.append((max(semis) - min(semis), voice, semis, max(dbs) - min(dbs)))
for spread, voice, semis, db in sorted(rows):
    print(f"{voice:13} pitch spread {spread:4.1f} st  loudness spread {db:4.1f} dB   per sentence: " + "  ".join(f"{s:+.1f}" for s in semis))

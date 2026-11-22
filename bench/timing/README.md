# Word timing

Phonon gives no word timings, so Berang estimates when each word starts from the audio (`mac/Sources/Speakable/Timing.swift`). This bench compares those estimates with forced alignment of the same audio by wav2vec2, which serves as the reference.

## Results

The error is the estimated start minus the reference start, per word. Phonon ran on an M1 with 8 GB of memory.

| Set | Method | Words | Median error | p90 error | Within 150 ms | Bias |
|---|---|---|---|---|---|---|
| corpus.txt, 137 chunks | Spread by characters | 2230 | 193 ms | 504 ms | 36.9% | +222 ms |
| corpus.txt, 137 chunks | Berang | 2230 | 66 ms | 310 ms | 75.6% | +80 ms |
| held-out.txt, 56 chunks | Spread by characters | 1001 | 208 ms | 539 ms | 34.7% | +215 ms |
| held-out.txt, 56 chunks | Berang | 1001 | 96 ms | 439 ms | 62.8% | +69 ms |

The weights were fitted on corpus.txt. held-out.txt comes from two pages that the fit did not use, so its row is the fair one. On held-out text, 63% of words are within 150 ms, against 35% for spreading by characters. The 150 ms target of #8 is not met for every word. The largest errors likely come from chunks where the voice skipped or misread text.

Estimating all 137 chunks, 830 s of audio, takes 358 ms, including reading the WAV files.

## Run

From `mac/`:

```sh
python3 ../bench/timing/corpus.py             # or --held-out
swift run -c release berang-say synth ../bench/timing/corpus.txt DIR
swift run -c release berang-say estimate DIR
uv run ../bench/timing/align.py DIR           # once per synth; writes DIR/reference.json
python3 ../bench/timing/compare.py DIR
```

`align.py` downloads the wav2vec2 model, about 360 MB, on its first run.

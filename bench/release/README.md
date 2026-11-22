# Release checks

Run before each release (#13). It measures four targets on the app's own text cleanup and voice, through `berang-say`:

```sh
bench/release/check.sh
```

| Target | Goal | How it is measured |
|---|---|---|
| Time to first word | under 300 ms | From a paragraph's text to the first word's sound in its first chunk, on a voice that is already loaded, over the 31 hard-text and held-out paragraphs. It includes text cleanup and the first chunk's synthesis. It leaves out reading the page, which takes a few milliseconds, and the audio output delay, about 1 ms on built-in speakers and more on Bluetooth. |
| Word errors on hard text | under 3% | Parakeet transcribes the voice reading the cleanup cases of six or more words (`hard.py`). The transcripts are scored against what a careful reader would say, with the normalizer in `bench/score.py`. |
| Highlight drift | under 150 ms | The median distance between each word's estimated start and its forced-aligned start, on the held-out timing paragraphs. See `bench/timing`. |
| Peak memory | under 300 MB | The largest resident set of `berang-say` while it synthesizes either set. The app adds its window and page reading on top. |

The first run downloads the alignment model, about 360 MB, and Parakeet, about 2.5 GB.

## Results

M1, 8 GB, macOS 26.6, on 2026-11-22 at commit 959c80b:

| Target | Goal | Measured | Met |
|---|---|---|---|
| Time to first word | under 300 ms | median 216 ms, max 266 ms, 31 paragraphs | yes |
| Word errors on hard text | under 3% | 0.0% of 154 words | yes |
| Highlight drift | under 150 ms | median 96 ms, p90 439 ms, 63% of 1001 words within 150 ms | yes |
| Peak memory | under 300 MB | 169 MB | yes |

The hard-text set is small: one wrong word is 0.65%. Drift meets its goal at the median only. One word in ten is off by 439 ms or more.

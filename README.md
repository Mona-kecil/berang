# berang

A free text-to-speech reader that runs on your own machine. Press play and it reads the page or document in front of you, with highlighting, speed control, and optionally your own cloned voice. Nothing is sent to a server.

Status: choosing the voice engine. The macOS app comes next.

## Engine benchmark

`bench/` compares 11 local voice models plus the macOS system voice on an M1 MacBook Air (8 GB). 2 CPU threads stand in for an iPhone 13. Full table: [`bench/results/summary.md`](bench/results/summary.md).

| Model | Download | First audio | Generation time per second of audio | License |
|---|---|---|---|---|
| Phonon 31m | 62 MB | 0.02 s | 0.06 s | Apache-2.0 |
| Kitten 2 nano | 28 MB | 0.65 s | 0.12 s | Apache-2.0 |
| Pocket 100M | 215 MB | 0.07 s | 0.28 s | CC-BY-4.0 |

Medians of 3 runs at 2 threads. On plain prose, every model's speech transcribes back with 0–1% word errors. On text with numbers, dates, and URLs, the error rate is 11–31% raw and about 5% after `bench/clean/`.

Pocket 100M can clone a voice from about 10 seconds of audio. Its cloning weights are gated: accept the terms at [kyutai/pocket-tts](https://huggingface.co/kyutai/pocket-tts) and set `HF_TOKEN`.

### Run it

Requires an Apple silicon Mac, [uv](https://docs.astral.sh/uv/), ffmpeg, and git. Setup downloads about 5 GB of models and environments into `bench/`.

```sh
bench/setup.sh            # create environments and download models
bench/bench.sh            # about 1.5 hours; writes bench/results/
python3 bench/report.py   # print the table
```

To compare raw and cleaned text, run `python3 bench/clean/make_corpus.py`, then `bench/clean_bench.sh`. To build a listening page with word highlighting, run `python3 bench/listen/build.py`; it writes `bench/listen/index.html`.

## Text cleanup

Before text reaches the voice model, `bench/clean/clean.py` rewrites it into speakable form: money, dates, times, units, versions, and abbreviations become words, URLs become "link to example dot com", and footnotes, hashes, and markup are removed. Each spoken word keeps its position in the source text, so the reader can highlight the original `$3.5M` while saying "three point five million dollars". It uses only the Python standard library.

```sh
python3 bench/clean/test_clean.py
echo 'Dr. Patel raised $3.5M on 2026-11-22.' | python3 bench/clean/clean.py
```

## License

The code is GPL-3.0. Model weights are not part of this repository, and each keeps its own license.

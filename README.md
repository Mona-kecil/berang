# berang

A free text-to-speech reader that runs on your own machine. Press play and it reads the page or document in front of you, with highlighting, speed control, and optionally your own cloned voice. Nothing is sent to a server.

Status: a first Mac player reads web pages and documents aloud. See the [milestones](https://github.com/Mona-kecil/berang/milestones) for what comes next.

## Engine benchmark

`bench/` measures berang's three voices on an M1 MacBook Air (8 GB). 2 CPU threads stand in for an iPhone 13. Full table: [`bench/results/summary.md`](bench/results/summary.md). The three were picked from 11 local models and the macOS system voice; that comparison is in commit 30e6f5e.

| Model | Download | First audio | Generation time per second of audio | License |
|---|---|---|---|---|
| Phonon 31m | 62 MB | 0.02 s | 0.06 s | Apache-2.0 |
| Kitten 2 nano | 28 MB | 0.65 s | 0.12 s | Apache-2.0 |
| Pocket 100M | 215 MB | 0.07 s | 0.28 s | CC-BY-4.0 |

Medians of 3 runs at 2 threads. On plain prose, each voice's speech transcribes back with no word errors. On text with numbers, dates, and URLs, the error rate is 11–24% raw and 2–8% after `bench/clean/`.

Pocket 100M can clone a voice from about 10 seconds of audio. Its cloning weights are gated: accept the terms at [kyutai/pocket-tts](https://huggingface.co/kyutai/pocket-tts) and set `HF_TOKEN`.

### Run it

Requires an Apple silicon Mac, [uv](https://docs.astral.sh/uv/), and ffmpeg. Setup puts about 6 GB of models and environments into `bench/`.

```sh
bench/setup.sh            # create environments and download models
bench/bench.sh            # about 10 minutes; writes bench/results/
python3 bench/report.py   # print the table
```

To compare raw and cleaned text, run `python3 bench/clean/make_corpus.py`, then `bench/clean_bench.sh`. To build a listening page with word highlighting, run `python3 bench/listen/build.py`; it writes `bench/listen/index.html`.

## Text cleanup

Before text reaches the voice model, `bench/clean/clean.py` rewrites it into speakable form: money, dates, times, units, versions, and abbreviations become words, URLs become "link to example dot com", and footnotes, hashes, and markup are removed. Each spoken word keeps its position in the source text, so the reader can highlight the original `$3.5M` while saying "three point five million dollars". It uses only the Python standard library.

```sh
python3 bench/clean/test_clean.py
echo 'Dr. Patel raised $3.5M on 2026-11-22.' | python3 bench/clean/clean.py
```

## Mac app

`mac/` holds Berang.app, a floating player that reads the window you were last in, using the Phonon 31m voice and highlighting the paragraph being read. Requires macOS 15 on Apple silicon, and Xcode to build.

```sh
mac/build-app.sh
open mac/build/Berang.app
```

The first time you press play, macOS asks to let Berang control your computer using accessibility features. Berang needs this to read text from other apps. Turn Berang on in System Settings > Privacy & Security > Accessibility, then press play again. On the first play, Berang downloads the voice (137 MB) from the Phonon release and checks its SHA-256.

`build-app.sh` signs the app with your Developer ID or Apple Development certificate. Without one, it signs ad hoc, and macOS forgets the Accessibility permission on every rebuild.

Right-click the player to quit.

### Text grabber

`berang-grab` in `mac/` uses the macOS Accessibility API to print a window's main text as Markdown. It reads the article and skips menus, sidebars, buttons, data tables, and back matter such as References. With no arguments, it reads the focused window of the frontmost app.

```sh
cd mac && swift build -c release
.build/release/berang-grab com.apple.Safari | python3 ../bench/clean/clean.py
swift test
```

It reads other apps' text, so the app that runs it, such as your terminal, needs Accessibility access in System Settings > Privacy & Security > Accessibility.

## License

The code is GPL-3.0. Model weights are not part of this repository, and each keeps its own license.

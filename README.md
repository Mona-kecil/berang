# Berang

Berang reads aloud the page, document, or book in front of you on your Mac. The voice runs on the Mac itself, so nothing you read is sent to a server. It is free and open source.

## Install

You need a Mac with Apple silicon and macOS 15 or later. Open Terminal and run:

```sh
curl -fsSL https://raw.githubusercontent.com/Mona-kecil/berang/main/install.sh | sh
```

This puts Berang in your Applications folder and opens it. Run the same command again to update.

Prefer not to use Terminal? Download `Berang.zip` from the [latest release](https://github.com/Mona-kecil/berang/releases/latest), unzip it, and move Berang to Applications. Berang is not notarized by Apple, so the first time you open it, macOS says it can't. Go to System Settings > Privacy & Security and click Open Anyway.

## Get started

1. Open a web page, and press ⌥⎋ (Option-Escape).
2. macOS asks to let Berang use accessibility features, which it needs to read other apps. Turn Berang on in System Settings > Privacy & Security > Accessibility, and press ⌥⎋ again.
3. The first time, Berang downloads its voice (137 MB), then starts reading.

## Use Berang

| To | Do this |
|---|---|
| Start or pause reading | Press ⌥⎋ in any app |
| Read part of the screen | Press ⌥⇧⎋ (Option-Shift-Escape) and drag over it |
| Listen to a whole book or file | Choose Open File from the menu bar, or open the file with Berang in Finder |
| Skip, change speed, or stop | Use the floating player |
| Show or hide the player, or quit | Click the waveform icon in the menu bar |

Reading starts at the text you selected, at the paragraph you clicked, or at the first paragraph on screen. On a page you read before, Berang continues where you stopped; Start over goes back to the top. Berang remembers the speed you choose.

## What Berang reads

- **Web pages** in Safari and Chrome. Berang skips menus, sidebars, ads, buttons, code, figures, and reference lists, and highlights the sentence and word it is reading.
- **Documents** in apps such as TextEdit.
- **PDFs** in Preview, Safari, and Chrome, without headers, footers, or page numbers.
- **Books and files** from Open File: EPUB, PDF, image, and text files, read from start to end. A book starts after its cover and contents, and continues where you stopped.
- **The page on screen in Apple Books.**
- **Images** open in Preview, by recognizing their text.
- **VS Code and Cursor**, from the cursor. Turn on screen reader mode first with ⇧⌥F1.
- **Google Docs**, the whole document. Turn on screen reader support and braille support first, under Tools > Accessibility.
- **Apps that draw their own text**, such as web readers that show pages as images. Berang recognizes the text on screen. This needs Screen Recording access, as does ⌥⇧⎋.

In PDFs and Apple Books, Berang highlights the paragraph rather than the word. VS Code, Google Docs, and recognized text have no highlight.

## Privacy

Berang reads and speaks on your Mac. It connects to the internet only to download its voice, once, from the [Phonon release](https://github.com/gradium-ai/xn-ptts/releases/tag/v0.7.1), and checks the download against a known fingerprint. It asks for two permissions:

- **Accessibility**, to read the text of other apps.
- **Screen Recording**, only if you use ⌥⇧⎋ or read an app that draws its own text. Berang recognizes the text on your Mac and keeps no images.

## Uninstall

Quit Berang from the menu bar, then delete:

- Berang from your Applications folder.
- The voice, about 300 MB, in `~/Library/Application Support/PhononTTS`.
- Your reading positions and speed, in `~/Library/Preferences/io.github.mona-kecil.berang.plist`.

You can also remove Berang from System Settings > Privacy & Security > Accessibility and Screen & System Audio Recording.

## What's next

Your own cloned voice, more languages, an onboarding guide, settings, and an iPhone app are planned. See the [milestones](https://github.com/Mona-kecil/berang/milestones).

## For developers

### Build from source

Building needs Xcode.

```sh
mac/build-app.sh
open mac/build/Berang.app
```

`build-app.sh` signs the app with the Berang certificate if your keychain has it, or else your Developer ID or Apple Development certificate. Without one, it signs ad hoc, and macOS forgets the Accessibility permission on every rebuild. To publish a release, push a tag such as `v0.2.0`; the Release workflow builds Berang, signs it with the Berang certificate from the repository secrets, and attaches `Berang.zip` to the release. `install.sh` installs only a Berang signed with that certificate.

### Engine benchmark

`bench/` measures berang's three voices on an M1 MacBook Air (8 GB). 2 CPU threads stand in for an iPhone 13. Full table: [`bench/results/summary.md`](bench/results/summary.md). The three were picked from 11 local models and the macOS system voice; that comparison is in commit 30e6f5e.

| Model | Download | First audio | Generation time per second of audio | License |
|---|---|---|---|---|
| Phonon 31m | 62 MB | 0.02 s | 0.06 s | Apache-2.0 |
| Kitten 2 nano | 28 MB | 0.65 s | 0.12 s | Apache-2.0 |
| Pocket 100M | 215 MB | 0.07 s | 0.28 s | CC-BY-4.0 |

Medians of 3 runs at 2 threads. On plain prose, each voice's speech transcribes back with no word errors. On text with numbers, dates, and URLs, the error rate is 11–24% raw and 2–8% after `bench/clean/`.

Pocket 100M can clone a voice from about 10 seconds of audio. Its cloning weights are gated: accept the terms at [kyutai/pocket-tts](https://huggingface.co/kyutai/pocket-tts) and set `HF_TOKEN`.

#### Run the benchmark

Requires an Apple silicon Mac, [uv](https://docs.astral.sh/uv/), and ffmpeg. Setup puts about 6 GB of models and environments into `bench/`.

```sh
bench/setup.sh            # create environments and download models
bench/bench.sh            # about 10 minutes; writes bench/results/
python3 bench/report.py   # print the table
```

Before each release, run `bench/release/check.sh`; it measures time to first word, word errors on hard text, highlight drift, and memory, and `bench/release/README.md` keeps the results. To compare raw and cleaned text, run `python3 bench/clean/make_corpus.py`, then `bench/clean_bench.sh`. To build a listening page with word highlighting, run `python3 bench/listen/build.py`; it writes `bench/listen/index.html`.

### Text cleanup

Before text reaches the voice model, `bench/clean/clean.py` rewrites it into speakable form: money, dates, times, units, versions, and abbreviations become words, URLs become "link to example dot com", and footnotes, hashes, and markup are removed. Each spoken word keeps its position in the source text, so the reader can highlight the original `$3.5M` while saying "three point five million dollars". It uses only the Python standard library. The Mac app speaks through a Swift port in `mac/Sources/Speakable`, and both versions are tested against the cases in `bench/clean/cases.json`.

```sh
python3 bench/clean/test_clean.py
echo 'Dr. Patel raised $3.5M on 2026-11-22.' | python3 bench/clean/clean.py
```

### Text grabber

`berang-grab` in `mac/` uses the macOS Accessibility API to print a window's main text as Markdown. It reads the article and skips menus, sidebars, buttons, data tables, code blocks, figures with their captions, ad slots, and back matter such as References. With no arguments, it reads the focused window of the frontmost app.

```sh
cd mac && swift build -c release
.build/release/berang-grab com.apple.Safari | python3 ../bench/clean/clean.py
swift test
```

It reads other apps' text, so the app that runs it, such as your terminal, needs Accessibility access in System Settings > Privacy & Security > Accessibility.

`swift test` also reads 29 saved pages in `mac/Tests/TextGrabTests/Pages`: openly licensed web pages saved from WebKit and Chrome, two TextEdit documents, a VS Code editor, and five PDFs. Each page keeps its accessibility tree, compressed, and the Markdown the grabber read from it, so a change to the grabber shows up as a diff in the `.md` files. `pages.tsv` lists each page's source and license. To record pages again, run `mac/Tests/TextGrabTests/Pages/record.sh [name ...]`. After a change to the grabber, `berang-grab --replay page.json.lzma` prints what it now reads from a saved page.

## License

The code is GPL-3.0. Model weights are not part of this repository, and each keeps its own license.

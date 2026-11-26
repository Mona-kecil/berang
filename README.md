# Berang

Berang reads aloud the page, document, or book in front of you on your Mac. The voice runs on the Mac itself, so nothing you read is sent to a server. It is free and open source.

## Install

You need a Mac with Apple silicon and macOS 15 or later. Open Terminal and run:

```sh
curl -fsSL https://raw.githubusercontent.com/Mona-kecil/berang/main/install.sh | sh
```

This puts Berang in your Applications folder and opens it. From version 0.1.2, Berang updates itself: see [Updates](#updates). To update an older version, run the same command again.

Prefer not to use Terminal? Download `Berang.zip` from the [latest release](https://github.com/Mona-kecil/berang/releases/latest), unzip it, and move Berang to Applications. Berang is not notarized by Apple, so the first time you open it, macOS says it can't. Go to System Settings > Privacy & Security and click Open Anyway.

## Get started

When Berang first opens, its window walks you through what it needs:

1. **Let me read other apps**: Accessibility, so Berang can read the text in other apps. Click Allow. Berang opens System Settings and floats a small guide beside it: switch Berang on. If Berang isn't in the list, drag the guide's icon into it. When it's on, Berang comes back to the front.
2. **Pick my voice.** Hear each one, then download its engine once: Kitten (82 MB, 10 voices), Phonon (137 MB, 38 voices), or Pocket (240 MB, 8 voices). Setup starts on Eleanor, a Kitten voice.

Berang asks for Screen Recording the first time you read a screen area or an app that draws its own text, with the same guide. After you switch it on, choose Quit & Reopen when macOS offers it.

Then press ⌥⎋ (Option-Escape) on any page.

## Use Berang

Berang lives in the menu bar, as an otter peeking over the waterline. Its menu holds what must be quick; everything else is in its window, under Open Berang.

| To | Do this |
|---|---|
| Start or pause reading | Press ⌥⎋ in any app |
| Read from somewhere else on the page | While Berang reads, select text there and press ⌥⎋ |
| Read part of the screen | Press ⌥⇧⎋ (Option-Shift-Escape) and drag over it |
| Listen to a whole book or file | Drop it on Berang's window or open it with Berang, then click Read |
| Skip or stop | Point at the floating player, which shows while Berang reads at the edge of the screen. Drag it to either side; it stays there |
| Change the speed | Click the speed in the player, or scroll over the player. While Berang reads, ⌥⇧. reads faster and ⌥⇧, slower, by 0.1× |
| Hear and choose a voice | In Berang's window, click your voice. Select any voice to hear it, or type your own words below the list and click Read |
| Change a shortcut | In Berang's window, open Settings, click the shortcut, and press the new keys |
| Quit | Choose Quit Berang from the menu bar |

Reading starts at the text you selected, at the paragraph you clicked, or at the first paragraph on screen. On a page you read before, Berang continues where you stopped; Start over goes back to the top. Berang remembers the speed you choose, from 0.5× to 3×. Under the speed, the player shows about how many words a minute you hear, measured from what the voice has read. Click the speed there to go back to 1×.

While you read, the player shows one short tip at a time: reading from somewhere else, changing the speed, moving the player, and pointing at it for more controls. A tip goes away once you use what it shows or dismiss it, and after three readings anyway.

### Shortcuts

Berang refuses a new shortcut, and says why, when:

- macOS or another app uses it;
- another Berang shortcut uses it;
- every app uses it for a command, like ⌘C for Copy;
- it has no ⌘, ⌥ or ⌃.

To see whether another app uses a key, Berang watches the keys you press while you record a shortcut, and only then. If another app later takes a key Berang uses, Berang can't tell; change the shortcut if it stops working.

Berang holds the faster and slower shortcuts only while it reads. The rest of the time, those keys reach the app you're in, where ⌥⇧. types ˘.

### Updates

Berang checks for a new version once a day. If it finds one while you work in another app, the menu bar icon shows a dot and the menu shows Update to, followed by the version. Choose it, then Install Update. Berang installs the update when you choose Install and Relaunch, or when you quit. Your voices, reading positions, and permissions stay.

Each update must be signed with Berang's update key and its certificate, or Berang refuses it.

## What Berang reads

- **Web pages** in Safari and Chrome. Berang skips menus, sidebars, ads, buttons, code, figures, and reference lists, and highlights the sentence and word it is reading.
- **Documents** in apps such as TextEdit.
- **PDFs** in Preview, Safari, and Chrome, without headers, footers, or page numbers.
- **Books and files** from Open File: EPUB, PDF, image, and text files, read from start to end. A book starts after its cover and contents, and continues where you stopped.
- **The page on screen in Apple Books.**
- **Images** open in Preview, by recognizing their text.
- **VS Code and Cursor**, from the cursor. Turn on screen reader mode first with ⇧⌥F1.
- **Google Docs**, the whole document. Turn on screen reader support and braille support first, under Tools > Accessibility.
- **Apps that draw their own text**, such as web readers that show pages as images. Berang recognizes the text on screen. This needs Screen Recording access, as does ⌥⇧⎋. Berang asks the first time you need it.

In PDFs and Apple Books, Berang highlights the paragraph rather than the word. VS Code, Google Docs, and recognized text have no highlight.

## Privacy

Berang reads and speaks on your Mac. It connects to the internet only to download a voice engine, once: Phonon from the [Phonon release](https://github.com/gradium-ai/xn-ptts/releases/tag/v0.7.1), checked against a known fingerprint; Kitten, if you choose one of its voices, from [KittenML](https://huggingface.co/KittenML/kitten-tts-2-nano) with its word lists from [Hugging Face](https://huggingface.co/beshkenadze/kitten-tts-g2p); and Pocket, if you choose one of its voices, from [Hugging Face](https://huggingface.co/mlx-community/pocket-tts). Once a day, it also checks [GitHub](https://github.com/Mona-kecil/berang/releases) for a new version. The check sends nothing about you or your Mac. It asks for two permissions:

- **Accessibility**, to read the text of other apps, and to see which keys you press while you record a shortcut.
- **Screen Recording**, only if you use ⌥⇧⎋ or read an app that draws its own text. Berang recognizes the text on your Mac and keeps no images.

## Uninstall

Quit Berang from the menu bar, then delete:

- Berang from your Applications folder.
- The Phonon voice engine, about 300 MB, in `~/Library/Application Support/PhononTTS`.
- The Kitten and Pocket voice engines, if you downloaded them, 94 MB and 229 MB, in `~/Library/Application Support/Berang`.
- Your reading positions, speed, and update settings, in `~/Library/Preferences/io.github.mona-kecil.berang.plist`.
- Downloaded updates and other caches, in `~/Library/Caches/io.github.mona-kecil.berang`.

You can also remove Berang from System Settings > Privacy & Security > Accessibility and Screen & System Audio Recording.

## What's next

Your own cloned voice, more languages, more settings, and an iPhone app are planned. See the [milestones](https://github.com/Mona-kecil/berang/milestones).

## For developers

### Build from source

Building needs Xcode.

```sh
mac/build-app.sh
open mac/build/Berang.app
```

`build-app.sh` signs the app with the Berang certificate if your keychain has it, or else your Developer ID or Apple Development certificate. Without one, it signs ad hoc, and macOS forgets the Accessibility permission on every rebuild. To publish a release, push a tag such as `v0.2.0`; the Release workflow builds Berang, signs it with the Berang certificate from the repository secrets, and attaches `Berang.zip` to the release. `install.sh` installs only a Berang signed with that certificate.

### Player model

`mac/Model/Player.tla` is a TLA+ model of the player: what each request does, step by step, while the voice downloads, loads, waits for an area, or reads. It has two engines, so it covers switching between them. TLC checks that Berang:

- never reads two things at once;
- never shows playing when nothing plays;
- keeps the highlight and saved position on what you hear;
- reads a request made while the voice gets ready, even if you choose a voice of another engine meanwhile;
- reads with the engine of the voice you chose;
- stages dropped or opened files in the window instead of speaking unprompted;
- keeps the player visible in a recognizing state while OCR runs on a screen area or drawn-text window.

With `Fixed = FALSE`, it checks choosing voices as it worked before, and TLC finds Berang asking one engine for another engine's voice. With `StageOnDrop = FALSE`, dropping a file speaks immediately and violates `NoAutoReadOnDrop`. With `ShowRecognizing = FALSE`, OCR runs with the player hidden and violates `FeedbackDuringOCR`. CI runs it; to run it yourself, see the command at the top of the file. Update it with any change to how `Player.swift` handles requests.

### Shortcut model

`mac/Model/Shortcuts.tla` models changing the shortcuts while other apps register and drop key combinations. macOS lets several apps register one combination and sends its presses to the latest, so the model includes that. TLC checks that:

- a failed change leaves a working shortcut working;
- Settings never shows a shortcut as working while Berang holds nothing for it;
- Berang holds the faster and slower shortcuts only while it reads;
- no two shortcuts share a combination;
- Berang never takes a combination that went to another app when you pressed it;
- recording never starts a reading or changes the speed.

With `SafeOrder = FALSE`, the change lets go of the old combination before registering the new one, and TLC finds a failed change losing the shortcut. With `Watch = FALSE`, Berang doesn't watch the keyboard while recording, and TLC finds it taking another app's combination. With `Release = FALSE`, a speed shortcut recorded while Berang doesn't read stays registered, and TLC finds Berang holding it with the player closed.

The check runs with read the page, read an area, and one speed shortcut, as the two speed shortcuts behave alike; it covers 5.6 million states in about a minute. To also check both speed shortcuts together, set `Always = {"page"}` and `WhileReading = {"faster", "slower"}` in `Shortcuts.cfg`.

### Jump model

`mac/Model/Jump.tla` models reading from a selection while Berang reads: you select text and press ⌥⎋, while you also switch windows, follow links, and use the player. TLC checks that:

- reading moves only to text selected since reading started or last moved, so a press meant to pause pauses;
- reading moves only within the page being read, never to a selection in another window, tab, or a page a link opened;
- only the shortcut moves reading; a click or a selection alone never does.

With `Remember = FALSE`, Berang forgets the selection it moved to, and TLC finds a press meant to pause moving reading back to it. With `AskReadPage = FALSE`, Berang asks the window in front, and TLC finds it moving reading to a selection made in another page.

### Placement model

`mac/Model/Place.tla` models where the floating player sits while displays connect and disconnect, also while the player is hidden or Berang is quit. The player rests against the left or right edge of a display; when you drop it, it slides to the nearer edge at the height you dropped it. A spot is a display, an edge, and a height. TLC checks that:

- a shown player is always on a display you have;
- the spot Berang keeps is always one you dragged the player to, never where macOS put it;
- whenever that spot's display is connected, a shown player is at your spot.

With `SaveOnAnyMove = TRUE`, Berang saves every move of the player, and TLC finds your spot replaced by where macOS put the player when you unplugged a display.

### Permission model

`mac/Model/Permission.tla` models the guide that floats beside System Settings while you switch on Accessibility or Screen Recording: you click Allow, open and close System Settings, switch the permission on and off, and close the guide, while Berang checks once a second and looks for Settings' window many times a second. TLC checks that:

- after a check that finds Accessibility on, no guide asks for it;
- Berang comes to the front only after a grant you started from Berang, and at most once per grant;
- never more than one guide shows;
- a guide closes when System Settings has been gone for a moment, but waits longer until it has found Settings' window, and asking again while Settings is open finds it at once;
- a failure shown for lacking Accessibility clears when the check finds it on.

With `CloseOnGrant = FALSE`, the guide stays after the check sees access on, and TLC finds it still showing. With `FrontOnlyIfAsked = FALSE`, TLC finds Berang coming to the front for a switch you turned on yourself. With `ReplaceOldGuide = FALSE`, TLC finds two guides at once. With `WaitForLaunch = FALSE`, TLC finds the guide closing while Settings still opens. With `CloseWhenSettingsGone = FALSE`, TLC finds the guide staying after you close Settings. With `ObserveOnShow = FALSE`, TLC finds a guide shown while Settings is open that has not found its window. With `ClearOnGrant = FALSE`, TLC finds the player's failure outliving the check that found access on. Update it with any change to `PermissionGuide.swift`.

### Brand

`mac/App/Brand` holds the app icon, the menu bar icon, and the otter's poses. The otter was drawn with an image model, gpt-image-2.6-sunburst, from a written brief: a flat otter in deep teal, otter brown, cream, and one orange, with its natural face. The app icon is that artwork shaped into the macOS icon outline. The menu bar icon is a single-colour drawing traced into a PDF with potrace.

### Update model

`mac/Model/Update.tla` models updates through Sparkle alongside reading and voice engine downloads. Quitting or relaunching for an update can cut a download short. TLC checks that:

- an engine that looks installed is whole;
- only an update with both signatures intact replaces the app;
- no update installs an older build;
- only you stop the reading.

With `Fixed = FALSE`, it checks the install code before these checks existed. TLC then finds a Pocket download cut short after its first file, which left Pocket looking installed but unable to load.

### Releases

A `v*` tag makes the release workflow build, sign, and zip the app. It also writes `appcast.xml`, the feed Berang checks for updates, signed with the update key in the `SPARKLE_ED_KEY` secret. The key's public half is `SUPublicEDKey` in `mac/App/Info.plist`. Keep the private key: without it, Berang can't update itself to any later release.

### Voice previews

`mac/App/Previews` holds a few seconds of each voice, so you can hear it before downloading its engine. `berang-say previews mac/App/Previews <Pocket's model folder> <Kitten's folder>` makes them again. The Phonon clips come from Phonon 31m by Gradium (Apache-2.0), the Kitten clips from Kitten TTS 2 nano by KittenML (Apache-2.0), and the Pocket clips from Pocket TTS by Kyutai (CC-BY-4.0).

`mac/App/Previews/voices.json` gives each voice's gender, accent and style, which the Voices window groups and labels them by. `python3 voice-profiles.py <Phonon's voices.jsonl> <Kitten's config.json>`, run in `mac`, writes it from what each source publishes: [Phonon's voice list](https://huggingface.co/gradium/phonon-voices), Kitten's config, and for Pocket the speaker notes of the datasets its voices were recorded for ([VCTK](https://datashare.ed.ac.uk/handle/10283/3443), [EARS](https://github.com/facebookresearch/ears_dataset)). Four Pocket voices have no published accent.

### Kitten on MLX

Kitten TTS 2 nano ships for ONNX Runtime and PyTorch. `mac/Sources/Kitten` runs it on MLX instead: it is mlx-audio-swift's port of Kitten 0.8 (MIT, see `mac/Sources/Kitten/LICENSE`), at nano's sizes, with the decoder's learned norm scales, uniform starting phases as in Kitten's PyTorch code, and one copy of the decoder's frames instead of one per frame. `berang-say kitten <folder> <reference>` compares it with kittenml's PyTorch output for the same tokens with noise off: on "The team met to plan the next release." the durations match to 0.00001 frames, the pitch to 0.2 Hz except at the last frames, and the spectrograms correlate at 0.993. It speaks 3.2 s of audio in 0.11 s.

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

### Website

`site` is berang.monosodiums.com, served by Cloudflare from `site/public`. `site/public/_redirects` sends berang.monosodiums.com/install to `install.sh`, so the page's install line stays short. The page's audio and word timings come from `berang-say site site/text/<name>.txt <dir> kitten/eleanor`, which reads the text through Berang's own cleanup and voices. `site/tools/pitch.py <dir>` measures how much each voice's pitch and loudness change from sentence to sentence. Run `npx wrangler dev` in `site` to try it, and `npx wrangler deploy` to publish it.

## License

The code is GPL-3.0. Model weights are not part of this repository, and each keeps its own license. Updates use [Sparkle](https://sparkle-project.org) (MIT).

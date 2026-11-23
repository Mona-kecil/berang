---- MODULE Update ----
\* Berang updating itself through Sparkle while you read and download voice engines.
\*
\* Sparkle checks the feed on its own or when you ask. It offers only a newer build, and downloads it once you choose
\* to install, or on its own if you ticked "Automatically download and install updates". It keeps the download only
\* if its EdDSA signature and code signature check out. The new build replaces the app when you choose Install and
\* Relaunch, or when you quit.
\*
\* Quitting or relaunching cuts any engine download short, leaving some of its files on disk. Berang decides whether
\* an engine is installed by looking for one file, `Proof(e)`. The engine must be whole whenever that file is there.
\* Otherwise Berang tries to read with a broken engine and never offers the download again.
\*
\* With Fixed = FALSE, the model checks the code before this change:
\*   - Pocket looked for its weights, which arrive before its voices.
\*   - Kitten looked for its word list's folder, which exists before the files in it.
\*   - Phonon removed its folder and then copied the new one in file by file.
\* Check: java -cp tla2tools.jar tlc2.TLC -config Update.cfg Update.tla
EXTENDS Naturals, Sequences
CONSTANTS Fixed

Engines == {"phonon", "kitten", "pocket"}
\* What an engine's install writes, in order.
Steps(e) ==
    CASE e = "pocket" -> <<"weights", "voices", "manifest">>
      [] e = "kitten" -> <<"weights", "lexicon folder", "lexicon", "lexicon manifest">>
      [] e = "phonon" -> IF Fixed THEN <<"bundle">> ELSE <<"bundle.json", "every file begun", "every file whole">>
\* The step whose file Berang takes as proof the engine is installed.
Proof(e) ==
    IF Fixed THEN Len(Steps(e))
    ELSE CASE e = "pocket" -> 1 [] e = "kitten" -> 2 [] e = "phonon" -> 2

VARIABLES running, reading, written, fetching, version, feed, updater, archive, installedFrom, automatic
vars == <<running, reading, written, fetching, version, feed, updater, archive, installedFrom, automatic>>

Installed(e) == written[e] >= Proof(e)
Whole(e) == written[e] = Len(Steps(e))

Init ==
    /\ running = TRUE /\ reading = FALSE /\ fetching = "none"
    /\ written \in [Engines -> {0}]
    /\ version = 1 /\ feed \in 1..2
    /\ updater = "idle" /\ archive = "none" /\ installedFrom = "release" /\ automatic = FALSE

\* Reading needs a whole engine. An engine that only looks installed fails to load and reads nothing.
YouRead ==
    /\ running /\ ~reading /\ \E e \in Engines : Whole(e)
    /\ reading' = TRUE
    /\ UNCHANGED <<running, written, fetching, version, feed, updater, archive, installedFrom, automatic>>

YouStop ==
    /\ reading /\ reading' = FALSE
    /\ UNCHANGED <<running, written, fetching, version, feed, updater, archive, installedFrom, automatic>>

\* The Voices window offers Download for an engine that isn't installed, one download at a time.
YouDownload ==
    \E e \in Engines :
        /\ running /\ fetching = "none" /\ ~Installed(e)
        /\ fetching' = e
        /\ written' = IF Whole(e) THEN written ELSE [written EXCEPT ![e] = 0]
        /\ UNCHANGED <<running, reading, version, feed, updater, archive, installedFrom, automatic>>

FileArrives ==
    /\ fetching # "none"
    /\ written' = [written EXCEPT ![fetching] = @ + 1]
    /\ fetching' = IF written[fetching] + 1 = Len(Steps(fetching)) THEN "none" ELSE fetching
    /\ UNCHANGED <<running, reading, version, feed, updater, archive, installedFrom, automatic>>

\* A newer build may be published at any time.
NewRelease ==
    /\ feed < 3 /\ feed' = feed + 1
    /\ UNCHANGED <<running, reading, written, fetching, version, updater, archive, installedFrom, automatic>>

\* Sparkle checks once a day or when you choose Check for Updates; during an update, asking again shows it.
Check ==
    /\ running /\ updater = "idle" /\ updater' = "checking"
    /\ UNCHANGED <<running, reading, written, fetching, version, feed, archive, installedFrom, automatic>>

FeedAnswers ==
    /\ updater = "checking"
    /\ updater' = IF feed <= version THEN "idle" ELSE IF automatic THEN "downloading" ELSE "offered"
    /\ UNCHANGED <<running, reading, written, fetching, version, feed, archive, installedFrom, automatic>>

YouSayLater ==
    /\ updater = "offered" /\ updater' = "idle"
    /\ UNCHANGED <<running, reading, written, fetching, version, feed, archive, installedFrom, automatic>>

\* Install Update, optionally ticking "Automatically download and install updates in the future".
YouInstall ==
    /\ updater = "offered" /\ updater' = "downloading" /\ automatic' \in BOOLEAN
    /\ UNCHANGED <<running, reading, written, fetching, version, feed, archive, installedFrom>>

\* Whoever serves the download may serve a changed one.
ArchiveArrives ==
    /\ updater = "downloading" /\ updater' = "verifying"
    /\ archive' \in {"signed", "tampered"}
    /\ UNCHANGED <<running, reading, written, fetching, version, feed, installedFrom, automatic>>

\* Sparkle keeps an update only if both signatures check out, and otherwise shows an error.
Verify ==
    /\ updater = "verifying"
    /\ updater' = IF archive = "signed" THEN "ready" ELSE "idle"
    /\ archive' = IF archive = "signed" THEN archive ELSE "none"
    /\ UNCHANGED <<running, reading, written, fetching, version, feed, installedFrom, automatic>>

Install ==
    /\ version' = feed /\ installedFrom' = archive
    /\ updater' = "idle" /\ archive' = "none"

\* Install and Relaunch: Berang quits, the new build replaces it, and it opens again.
YouRelaunch ==
    /\ running /\ updater = "ready" /\ Install
    /\ reading' = FALSE /\ fetching' = "none"
    /\ UNCHANGED <<running, written, feed, automatic>>

\* Quitting installs an update that is ready.
YouQuit ==
    /\ running /\ running' = FALSE /\ reading' = FALSE /\ fetching' = "none"
    /\ IF updater = "ready" THEN Install ELSE updater' = "idle" /\ archive' = "none" /\ UNCHANGED <<version, installedFrom>>
    /\ UNCHANGED <<written, feed, automatic>>

YouOpen ==
    /\ ~running /\ running' = TRUE
    /\ UNCHANGED <<reading, written, fetching, version, feed, updater, archive, installedFrom, automatic>>

Next ==
    \/ YouRead \/ YouStop \/ YouDownload \/ FileArrives \/ NewRelease \/ Check \/ FeedAnswers \/ YouSayLater
    \/ YouInstall \/ ArchiveArrives \/ Verify \/ YouRelaunch \/ YouQuit \/ YouOpen

\* Once its download stops, an engine that looks installed is whole, so it reads. One that isn't whole offers its
\* download again.
InstalledMeansWhole == \A e \in Engines : Installed(e) /\ fetching # e => Whole(e)
\* Only a build with both signatures intact replaces the app.
OnlySignedBuilds == installedFrom \in {"release", "signed"}
\* An update never goes back to an older build.
NeverOlder == [][version' >= version]_version
\* Only you stop the reading: by pressing stop, quitting, or choosing to relaunch.
OnlyYouStopReading == [][reading /\ ~reading' => YouStop \/ YouQuit \/ YouRelaunch]_vars
====

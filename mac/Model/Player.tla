---- MODULE Player ----
\* Berang's player, Sources/Berang/Player.swift. Each request (press play, read an area, open a file, skip)
\* runs as a task that steps through stages. A request replaces the work before it, replaced work changes nothing,
\* and a request made while the voice downloads or loads waits for it.
\*
\* There are two engines. Choosing a voice plays its recorded clip at once, and loads its engine behind the clip if
\* that engine isn't the one loaded. A voice with no clip speaks a sample once its engine loads. A voice's clip also
\* plays without a download, beside a download or load.
\*
\* With Fixed = FALSE, choosing a voice works as before this change. It spoke a live sample after loading the
\* engine, and a voice chosen while an engine loaded was applied once that load finished. TLC finds that path:
\* choose a voice of one engine, then a voice of the other before the first engine loads, and Berang asks the first
\* engine for the second engine's voice and fails.
\* Check: java -cp tla2tools.jar tlc2.TLC -config Player.cfg Player.tla
EXTENDS Naturals, FiniteSets, Sequences
CONSTANTS MaxTasks, Fixed

Engines == {"A", "B"}

VARIABLES ui, voice, chosen, loadedEng, tasks, current, shown, reason, ignored, pending
vars == <<ui, voice, chosen, loadedEng, tasks, current, shown, reason, ignored, pending>>
Ids == 1..Len(tasks)

Init ==
    /\ ui = "idle" /\ voice \in {"missing", "installed"} /\ chosen = "A" /\ loadedEng = "none"
    /\ tasks = <<>> /\ current = 0 /\ shown = "none" /\ reason = "none"
    /\ ignored = FALSE /\ pending = "none"

Set(i, f, v) == [tasks EXCEPT ![i][f] = v]
Task(src, stage, e) == [src |-> src, stage |-> stage, cancelled |-> FALSE, eng |-> e]
\* cancel() stops the current task and any preview.
Cancelled(t) == [i \in DOMAIN t |-> IF i = current \/ t[i].stage = "clip" THEN [t[i] EXCEPT !.cancelled = TRUE] ELSE t[i]]
\* Reading or a sample starting ends a preview that played while the voice got ready.
Quiet(t) == [i \in DOMAIN t |-> IF t[i].stage = "clip" THEN [t[i] EXCEPT !.stage = "done"] ELSE t[i]]
Preparing == ui \in {"downloading", "loading"}

\* Where a request goes once the voice is ready: an area waits for a drag; a page or file reads,
\* unless the page's app draws its own text, which is recognized first.
Ready(src) == CASE src = "area" -> {<<"pick", "idle">>}
                [] src = "sample" -> {<<"sample", "idle">>}
                [] src = "file" -> {<<"read", "playing">>}
                [] OTHER -> {<<"read", "playing">>, <<"ocr", "idle">>}
FirstStages(src, e) ==
    IF loadedEng = e THEN Ready(src)
    ELSE IF voice = "missing" THEN {<<"download", "downloading">>} ELSE {<<"load", "loading">>}

\* Start request `src` with engine `e`, after cancelling the current work. Loading lets go of the loaded engine.
BeginWith(src, e) ==
    \E st \in FirstStages(src, e) :
        /\ tasks' = Append(Cancelled(tasks), Task(src, st[1], e))
        /\ current' = Len(tasks) + 1 /\ ui' = st[2]
        /\ shown' = IF st[1] = "read" THEN src ELSE "none"
        /\ loadedEng' = IF st[1] = "load" THEN "none" ELSE loadedEng
Begin(src) == BeginWith(src, chosen)

YouPressPlay ==
    /\ UNCHANGED <<voice, chosen, reason, ignored>>
    /\ \/ ui = "playing" /\ ui' = "paused" /\ UNCHANGED <<tasks, current, shown, pending, loadedEng>>
       \/ ui = "paused" /\ ui' = "playing" /\ UNCHANGED <<tasks, current, shown, pending, loadedEng>>
       \/ ui \in {"idle", "failed"} /\ Begin("window") /\ UNCHANGED pending
       \/ Preparing /\ pending' = "window" /\ UNCHANGED <<ui, tasks, current, shown, loadedEng>>

YouOpen(src) ==
    /\ UNCHANGED <<voice, chosen, reason, ignored>>
    /\ \/ Preparing /\ pending' = src /\ UNCHANGED <<ui, tasks, current, shown, loadedEng>>
       \/ ~Preparing /\ Begin(src) /\ UNCHANGED pending
YouOpenArea == YouOpen("area")
YouOpenFile == YouOpen("file")

YouPressStop ==
    /\ ui \in {"playing", "paused"}
    /\ tasks' = Cancelled(tasks) /\ ui' = "idle" /\ shown' = "none"
    /\ UNCHANGED <<current, voice, chosen, loadedEng, reason, ignored, pending>>

YouSkip ==
    /\ ui \in {"playing", "paused"} /\ current \in Ids
    /\ tasks' = Append(Cancelled(tasks), Task(tasks[current].src, "read", chosen))
    /\ current' = Len(tasks) + 1 /\ ui' = "playing"
    /\ UNCHANGED <<shown, voice, chosen, loadedEng, reason, ignored, pending>>

\* audition(): the voice's clip plays at once. If its engine isn't loaded, the engine loads behind the clip, and a
\* request already waiting keeps waiting for it.
Audition(e) ==
    LET withClip == Append(Cancelled(tasks), Task("clip", "clip", e)) IN
    /\ shown' = "none"
    /\ IF loadedEng = e
       THEN tasks' = withClip /\ current' = Len(tasks) + 1 /\ ui' = "idle" /\ UNCHANGED loadedEng
       ELSE /\ tasks' = Append(withClip, Task("voice", "load", e))
            /\ current' = Len(tasks) + 2 /\ ui' = "loading" /\ loadedEng' = "none"

\* choose(): while reading, the next sentence takes a voice of the same engine, which changes no state here. A voice
\* of the other engine stops the reading.
YouChooseVoiceNow(e) ==
    /\ voice = "installed" /\ chosen' = e
    /\ \/ ui \in {"idle", "failed"} /\ Audition(e) /\ UNCHANGED pending
       \/ ui \in {"playing", "paused"} /\ e # chosen /\ Audition(e) /\ UNCHANGED pending
       \* The load for a request gives way to the new engine's, and the request waits for that one.
       \/ ui = "loading" /\ Audition(e)
          /\ pending' = IF pending = "none" /\ tasks[current].src \in {"window", "area", "file"}
                        THEN tasks[current].src ELSE pending
       \* Beside a download the clip plays alone; the download then loads the chosen engine.
       \/ ui = "downloading" /\ tasks' = Append(Quiet(tasks), Task("clip", "clip", e))
          /\ UNCHANGED <<ui, current, shown, loadedEng, pending>>
    /\ UNCHANGED <<voice, reason, ignored>>

\* Before: a sample spoke once the engine loaded, and a voice chosen during a download or load waited for it.
YouChooseVoiceBefore(e) ==
    /\ voice = "installed" /\ chosen' = e
    /\ \/ ui \in {"idle", "failed"} /\ BeginWith("sample", e)
       \/ ui \in {"playing", "paused"} /\ e # chosen /\ BeginWith("sample", e)
       \/ Preparing /\ UNCHANGED <<ui, tasks, current, shown, loadedEng>>
    /\ UNCHANGED <<voice, reason, ignored, pending>>

YouChooseVoice == \E e \in Engines : IF Fixed THEN YouChooseVoiceNow(e) ELSE YouChooseVoiceBefore(e)

\* A voice with no recorded clip, such as one an engine adds later, speaks a sample instead.
YouChooseVoiceWithoutClip ==
    \E e \in Engines :
        /\ voice = "installed" /\ chosen' = e
        /\ \/ ui \in {"idle", "failed"}
           \/ ui \in {"playing", "paused"} /\ e # chosen
        /\ BeginWith("sample", e)
        /\ UNCHANGED <<voice, reason, ignored, pending>>

\* preview(): a voice of an engine not downloaded. Beside a download or load it plays alone; otherwise it replaces
\* what plays.
YouPreview ==
    /\ \/ Preparing /\ tasks' = Append(Quiet(tasks), Task("clip", "clip", chosen))
          /\ UNCHANGED <<ui, current, shown>>
       \/ ~Preparing /\ tasks' = Append(Cancelled(tasks), Task("clip", "clip", chosen))
          /\ current' = Len(tasks) + 1 /\ ui' = "idle" /\ shown' = "none"
    /\ UNCHANGED <<voice, chosen, loadedEng, reason, ignored, pending>>

ClipEndsOf(i) ==
    /\ tasks[i].stage = "clip" /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, chosen, loadedEng, current, shown, reason, ignored, pending>>

YouDownloadInSetup ==
    /\ voice = "missing" /\ ui \in {"idle", "failed"}
    /\ tasks' = Append(Cancelled(tasks), Task("setup", "download", chosen))
    /\ current' = Len(tasks) + 1 /\ ui' = "downloading" /\ shown' = "none"
    /\ UNCHANGED <<voice, chosen, loadedEng, reason, ignored, pending>>

\* --- the current task's steps --------------------------------------------
Live(i) == i = current /\ ~tasks[i].cancelled

GoOn(i, src) ==   \* the voice is ready: run the latest request
    \E st \in Ready(src) :
        /\ tasks' = [Quiet(tasks) EXCEPT ![i] = [@ EXCEPT !.src = src, !.stage = st[1]]]
        /\ ui' = st[2] /\ shown' = IF st[1] = "read" THEN src ELSE "none"

\* Once the engine is in, the task loads the engine chosen by then, letting go of the loaded one.
DownloadFinishesOf(i) ==
    /\ tasks[i].stage = "download" /\ Live(i) /\ voice' = "installed"
    /\ \/ tasks[i].src = "setup" /\ pending = "none"
          /\ tasks' = Set(i, "stage", "done") /\ ui' = "idle" /\ UNCHANGED <<shown, pending, loadedEng>>
       \/ (tasks[i].src # "setup" \/ pending # "none")
          /\ tasks' = [tasks EXCEPT ![i] = [@ EXCEPT !.stage = "load", !.eng = chosen,
                                              !.src = IF pending # "none" THEN pending ELSE @]]
          /\ ui' = "loading" /\ pending' = "none" /\ loadedEng' = "none" /\ UNCHANGED shown
    /\ UNCHANGED <<chosen, current, reason, ignored>>

DownloadFailsOf(i) ==
    /\ tasks[i].stage = "download" /\ Live(i)
    /\ tasks' = Set(i, "stage", "done") /\ ui' = "failed" /\ reason' = "network" /\ pending' = "none"
    /\ UNCHANGED <<voice, chosen, loadedEng, current, shown, ignored>>

\* loadVoice() conditions the loaded engine on the chosen voice. Before, a load finished with whatever voice was
\* chosen by then, even one of the other engine.
LoadFinishesOf(i) ==
    /\ tasks[i].stage = "load" /\ Live(i) /\ loadedEng' = tasks[i].eng
    /\ IF tasks[i].eng # chosen
       THEN /\ tasks' = Set(i, "stage", "done") /\ ui' = "failed" /\ reason' = "wrong engine" /\ pending' = "none"
            /\ UNCHANGED shown
       ELSE /\ UNCHANGED reason /\ pending' = "none"
            /\ IF tasks[i].src = "voice" /\ pending = "none"
               THEN tasks' = Set(i, "stage", "done") /\ ui' = "idle" /\ UNCHANGED shown
               ELSE GoOn(i, IF pending # "none" THEN pending ELSE tasks[i].src)
    /\ UNCHANGED <<voice, chosen, current, ignored>>

YouDragAnAreaOf(i) ==
    /\ tasks[i].stage = "pick" /\ Live(i)
    /\ tasks' = Set(i, "stage", "read") /\ ui' = "playing" /\ shown' = "area"
    /\ UNCHANGED <<voice, chosen, loadedEng, current, reason, ignored, pending>>

YouPressEscapeOf(i) ==
    /\ tasks[i].stage = "pick" /\ Live(i) /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, chosen, loadedEng, current, shown, reason, ignored, pending>>

TextRecognizedOf(i) ==
    /\ tasks[i].stage = "ocr" /\ Live(i)
    /\ tasks' = Set(i, "stage", "read") /\ ui' = "playing" /\ shown' = "window"
    /\ UNCHANGED <<voice, chosen, loadedEng, current, reason, ignored, pending>>

SampleEndsOf(i) ==
    /\ tasks[i].stage = "sample" /\ Live(i) /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, chosen, loadedEng, current, shown, reason, ignored, pending>>

PageEndsOf(i) ==
    /\ tasks[i].stage = "read" /\ Live(i) /\ ui = "playing"
    /\ tasks' = Set(i, "stage", "done") /\ ui' = "idle" /\ shown' = "none"
    /\ UNCHANGED <<voice, chosen, loadedEng, current, reason, ignored, pending>>

\* Stale work stops at its next step and changes nothing; a stale pick's crosshair closes.
StaleWorkEndsOf(i) ==
    /\ tasks[i].stage \notin {"done"} /\ ~Live(i)
    /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, chosen, loadedEng, current, shown, reason, ignored, pending>>

DownloadFinishes == \E i \in Ids : DownloadFinishesOf(i)
DownloadFails == \E i \in Ids : DownloadFailsOf(i)
LoadFinishes == \E i \in Ids : LoadFinishesOf(i)
YouDragAnArea == \E i \in Ids : YouDragAnAreaOf(i)
YouPressEscape == \E i \in Ids : YouPressEscapeOf(i)
TextRecognized == \E i \in Ids : TextRecognizedOf(i)
PageEnds == \E i \in Ids : PageEndsOf(i)
SampleEnds == \E i \in Ids : SampleEndsOf(i)
ClipEnds == \E i \in Ids : ClipEndsOf(i)
StaleWorkEnds == \E i \in Ids : StaleWorkEndsOf(i)

Next ==
    \/ YouPressPlay \/ YouOpenArea \/ YouOpenFile \/ YouPressStop \/ YouSkip \/ YouDownloadInSetup \/ YouChooseVoice
    \/ YouChooseVoiceWithoutClip \/ YouPreview
    \/ DownloadFinishes \/ DownloadFails \/ LoadFinishes \/ YouDragAnArea \/ YouPressEscape
    \/ TextRecognized \/ PageEnds \/ SampleEnds \/ ClipEnds \/ StaleWorkEnds

Spec == Init /\ [][Next]_vars

LiveReaders == {i \in Ids : tasks[i].stage = "read" /\ ~tasks[i].cancelled}
\* Readings, samples and clips all play sound.
OneThingAtATime == Cardinality({i \in Ids : tasks[i].stage \in {"read", "sample", "clip"} /\ ~tasks[i].cancelled}) <= 1
PlayingMeansSound == ui = "playing" => LiveReaders # {}
NoErrorFromStopping == reason # "cancelled"
NoIgnoredRequest == ~ignored
FollowsWhatYouHear == \A i \in LiveReaders : shown = tasks[i].src
\* A request made while the voice gets ready is read once it is ready, or the failure says why.
PendingOnlyWhilePreparing == pending # "none" => Preparing
\* A request isn't dropped while its voice gets ready: it is loading, or waiting, or it was replaced by another.
RequestsSurvive == \A i \in Ids :
    (tasks[i].cancelled /\ tasks[i].stage \in {"load", "download"} /\ tasks[i].src \in {"window", "area", "file"})
        => \/ pending # "none"
           \/ \E j \in Ids : j > i /\ tasks[j].src \in {"window", "area", "file"}
           \/ ui \notin {"loading", "downloading"}
\* Switching engines never leaves one engine asked for the other's voice.
NoWrongEngine == reason # "wrong engine"
\* What reads, reads with the engine of the voice you chose.
ReadsWithChosenEngine == LiveReaders # {} => loadedEng = chosen
Bound == Len(tasks) <= MaxTasks
====

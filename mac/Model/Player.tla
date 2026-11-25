---- MODULE Player ----
\* Berang's player, Sources/Berang/Player.swift. Each request (press play, read an area, read text, start a staged
\* file, skip) runs as a task that steps through stages. Dropping or opening a file stages it in the window without
\* playing until you click Read. A request replaces the work before it, replaced work changes nothing, and a request
\* made while the voice downloads or loads waits for it (whereas a request during OCR replaces the OCR at once).
\*
\* There are two engines. Choosing a voice plays its recorded clip at once, and loads its engine behind the clip if
\* that engine isn't the one loaded. A voice with no clip speaks a sample once its engine loads. A voice's clip also
\* plays without a download, beside a download or load.
\*
\* Safeguard constants (all TRUE in Player.cfg):
\* - Fixed = FALSE: choosing a voice of another engine while an engine loads asks the first engine for the second's
\*   voice and breaks NoWrongEngine.
\* - StageOnDrop = FALSE: dropping a file starts reading immediately without confirmation and breaks NoAutoReadOnDrop.
\* - ShowRecognizing = FALSE: OCR runs while ui stays "idle" (player hidden) and breaks FeedbackDuringOCR.
\* Check: java -cp tla2tools.jar tlc2.TLC -config Player.cfg -workers auto Player.tla
EXTENDS Naturals, FiniteSets, Sequences
CONSTANTS MaxTasks, Fixed, StageOnDrop, ShowRecognizing

Engines == {"A", "B"}

VARIABLES ui, voice, chosen, loadedEng, tasks, current, shown, reason, ignored, pending, staged
vars == <<ui, voice, chosen, loadedEng, tasks, current, shown, reason, ignored, pending, staged>>
Ids == 1..Len(tasks)

Init ==
    /\ ui = "idle" /\ voice \in {"missing", "installed"} /\ chosen = "A" /\ loadedEng = "none"
    /\ tasks = <<>> /\ current = 0 /\ shown = "none" /\ reason = "none"
    /\ ignored = FALSE /\ pending = "none" /\ staged = FALSE

Set(i, f, v) == [tasks EXCEPT ![i][f] = v]
Task(src, stage, e, delib) == [src |-> src, stage |-> stage, cancelled |-> FALSE, eng |-> e, deliberate |-> delib]
\* cancel() stops the current task and any preview.
Cancelled(t) == [i \in DOMAIN t |-> IF i = current \/ t[i].stage = "clip" THEN [t[i] EXCEPT !.cancelled = TRUE] ELSE t[i]]
Quiet(t) == [i \in DOMAIN t |-> IF t[i].stage = "clip" THEN [t[i] EXCEPT !.stage = "done"] ELSE t[i]]
Preparing == ui \in {"downloading", "loading"}
OcrUI == IF ShowRecognizing THEN "recognizing" ELSE "idle"

Ready(src) == CASE src = "area" -> {<<"pick", "idle">>}
                [] src = "sample" -> {<<"sample", "idle">>}
                [] src = "file" -> {<<"read", "playing">>}
                [] OTHER -> {<<"read", "playing">>, <<"ocr", OcrUI>>}
FirstStages(src, e) ==
    IF loadedEng = e THEN Ready(src)
    ELSE IF voice = "missing" THEN {<<"download", "downloading">>} ELSE {<<"load", "loading">>}

\* Start request `src` with engine `e`, after cancelling the current work. Loading lets go of the loaded engine.
BeginWith(src, e, delib) ==
    \E st \in FirstStages(src, e) :
        /\ tasks' = Append(Cancelled(tasks), Task(src, st[1], e, delib))
        /\ current' = Len(tasks) + 1 /\ ui' = st[2]
        /\ shown' = IF st[1] = "read" THEN src ELSE "none"
        /\ loadedEng' = IF st[1] = "load" THEN "none" ELSE loadedEng
Begin(src, delib) == BeginWith(src, chosen, delib)

YouPressPlay ==
    /\ UNCHANGED <<voice, chosen, reason, ignored, staged>>
    /\ \/ ui = "playing" /\ ui' = "paused" /\ UNCHANGED <<tasks, current, shown, pending, loadedEng>>
       \/ ui = "paused" /\ ui' = "playing" /\ UNCHANGED <<tasks, current, shown, pending, loadedEng>>
       \/ ui \in {"idle", "failed", "recognizing"} /\ Begin("window", TRUE) /\ UNCHANGED pending
       \/ Preparing /\ pending' = "window" /\ UNCHANGED <<ui, tasks, current, shown, loadedEng>>

YouOpen(src, delib) ==
    /\ UNCHANGED <<voice, chosen, reason, ignored>>
    /\ \/ Preparing /\ pending' = src /\ UNCHANGED <<ui, tasks, current, shown, loadedEng>>
       \/ ~Preparing /\ Begin(src, delib) /\ UNCHANGED pending
YouOpenArea == YouOpen("area", TRUE) /\ UNCHANGED staged
YouReadText == YouOpen("file", TRUE) /\ UNCHANGED staged

YouDropFile ==
    IF StageOnDrop THEN
        /\ staged' = TRUE
        /\ UNCHANGED <<ui, voice, chosen, loadedEng, tasks, current, shown, reason, ignored, pending>>
    ELSE
        /\ YouOpen("file", FALSE) /\ UNCHANGED staged

YouStartStaged ==
    /\ staged /\ staged' = FALSE
    /\ YouOpen("file", TRUE)

YouClearStaged ==
    /\ staged /\ staged' = FALSE
    /\ UNCHANGED <<ui, voice, chosen, loadedEng, tasks, current, shown, reason, ignored, pending>>

YouPressStop ==
    /\ ui \in {"playing", "paused", "recognizing", "failed"}
    /\ tasks' = Cancelled(tasks) /\ ui' = "idle" /\ shown' = "none"
    /\ UNCHANGED <<current, voice, chosen, loadedEng, reason, ignored, pending, staged>>

YouSkip ==
    /\ ui \in {"playing", "paused"} /\ current \in Ids
    /\ tasks' = Append(Cancelled(tasks), Task(tasks[current].src, "read", chosen, tasks[current].deliberate))
    /\ current' = Len(tasks) + 1 /\ ui' = "playing"
    /\ UNCHANGED <<shown, voice, chosen, loadedEng, reason, ignored, pending, staged>>

\* audition(): the voice's clip plays at once. If its engine isn't loaded, the engine loads behind the clip, and a
\* request already waiting keeps waiting for it.
Audition(e) ==
    LET withClip == Append(Cancelled(tasks), Task("clip", "clip", e, TRUE)) IN
    /\ shown' = "none"
    /\ IF loadedEng = e
       THEN tasks' = withClip /\ current' = Len(tasks) + 1 /\ ui' = "idle" /\ UNCHANGED loadedEng
       ELSE /\ tasks' = Append(withClip, Task("voice", "load", e, TRUE))
            /\ current' = Len(tasks) + 2 /\ ui' = "loading" /\ loadedEng' = "none"

\* choose(): while reading, the next sentence takes a voice of the same engine, which changes no state here. A voice
\* of the other engine stops the reading.
YouChooseVoiceNow(e) ==
    /\ voice = "installed" /\ chosen' = e
    /\ \/ ui \in {"idle", "failed", "recognizing"} /\ Audition(e) /\ UNCHANGED pending
       \/ ui \in {"playing", "paused"} /\ e # chosen /\ Audition(e) /\ UNCHANGED pending
       \* The load for a request gives way to the new engine's, and the request waits for that one.
       \/ ui = "loading" /\ Audition(e)
          /\ pending' = IF pending = "none" /\ tasks[current].src \in {"window", "area", "file"}
                        THEN tasks[current].src ELSE pending
       \* Beside a download the clip plays alone; the download then loads the chosen engine.
       \/ ui = "downloading" /\ tasks' = Append(Quiet(tasks), Task("clip", "clip", e, TRUE))
          /\ UNCHANGED <<ui, current, shown, loadedEng, pending>>
    /\ UNCHANGED <<voice, reason, ignored, staged>>

\* Before: a sample spoke once the engine loaded, and a voice chosen during a download or load waited for it.
YouChooseVoiceBefore(e) ==
    /\ voice = "installed" /\ chosen' = e
    /\ \/ ui \in {"idle", "failed", "recognizing"} /\ BeginWith("sample", e, TRUE)
       \/ ui \in {"playing", "paused"} /\ e # chosen /\ BeginWith("sample", e, TRUE)
       \/ Preparing /\ UNCHANGED <<ui, tasks, current, shown, loadedEng>>
    /\ UNCHANGED <<voice, reason, ignored, pending, staged>>

YouChooseVoice == \E e \in Engines : IF Fixed THEN YouChooseVoiceNow(e) ELSE YouChooseVoiceBefore(e)

\* A voice with no recorded clip, such as one an engine adds later, speaks a sample instead.
YouChooseVoiceWithoutClip ==
    \E e \in Engines :
        /\ voice = "installed" /\ chosen' = e
        /\ \/ ui \in {"idle", "failed", "recognizing"}
           \/ ui \in {"playing", "paused"} /\ e # chosen
        /\ BeginWith("sample", e, TRUE)
        /\ UNCHANGED <<voice, reason, ignored, pending, staged>>

\* preview(): a voice of an engine not downloaded. Beside a download or load it plays alone; otherwise it replaces
\* what plays.
YouPreview ==
    /\ \/ Preparing /\ tasks' = Append(Quiet(tasks), Task("clip", "clip", chosen, TRUE))
          /\ UNCHANGED <<ui, current, shown>>
       \/ ~Preparing /\ tasks' = Append(Cancelled(tasks), Task("clip", "clip", chosen, TRUE))
          /\ current' = Len(tasks) + 1 /\ ui' = "idle" /\ shown' = "none"
    /\ UNCHANGED <<voice, chosen, loadedEng, reason, ignored, pending, staged>>

ClipEndsOf(i) ==
    /\ tasks[i].stage = "clip" /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, chosen, loadedEng, current, shown, reason, ignored, pending, staged>>

YouDownloadInSetup ==
    /\ voice = "missing" /\ ui \in {"idle", "failed"}
    /\ tasks' = Append(Cancelled(tasks), Task("setup", "download", chosen, TRUE))
    /\ current' = Len(tasks) + 1 /\ ui' = "downloading" /\ shown' = "none"
    /\ UNCHANGED <<voice, chosen, loadedEng, reason, ignored, pending, staged>>

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
    /\ UNCHANGED <<chosen, current, reason, ignored, staged>>

DownloadFailsOf(i) ==
    /\ tasks[i].stage = "download" /\ Live(i)
    /\ tasks' = Set(i, "stage", "done")
    /\ (ui' = IF tasks[i].src = "setup" /\ pending = "none" THEN "idle" ELSE "failed")
    /\ reason' = "network" /\ pending' = "none"
    /\ UNCHANGED <<voice, chosen, loadedEng, current, shown, ignored, staged>>

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
    /\ UNCHANGED <<voice, chosen, current, ignored, staged>>

YouDragAnAreaOf(i) ==
    /\ tasks[i].stage = "pick" /\ Live(i)
    /\ tasks' = [Quiet(tasks) EXCEPT ![i] = [@ EXCEPT !.stage = "ocr"]]
    /\ ui' = OcrUI
    /\ UNCHANGED <<voice, chosen, loadedEng, current, shown, reason, ignored, pending, staged>>

YouPressEscapeOf(i) ==
    /\ tasks[i].stage = "pick" /\ Live(i) /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, chosen, loadedEng, current, shown, reason, ignored, pending, staged>>

TextRecognizedOf(i) ==
    /\ tasks[i].stage = "ocr" /\ Live(i)
    /\ tasks' = [Quiet(tasks) EXCEPT ![i] = [@ EXCEPT !.stage = "read"]]
    /\ ui' = "playing" /\ shown' = tasks[i].src
    /\ UNCHANGED <<voice, chosen, loadedEng, current, reason, ignored, pending, staged>>

TextRecognitionEmptyOf(i) ==
    /\ tasks[i].stage = "ocr" /\ Live(i)
    /\ tasks' = Set(i, "stage", "done") /\ ui' = "failed" /\ reason' = "no text" /\ shown' = "none"
    /\ UNCHANGED <<voice, chosen, loadedEng, current, ignored, pending, staged>>

SampleEndsOf(i) ==
    /\ tasks[i].stage = "sample" /\ Live(i) /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, chosen, loadedEng, current, shown, reason, ignored, pending, staged>>

PageEndsOf(i) ==
    /\ tasks[i].stage = "read" /\ Live(i) /\ ui = "playing"
    /\ tasks' = Set(i, "stage", "done") /\ ui' = "idle" /\ shown' = "none"
    /\ UNCHANGED <<voice, chosen, loadedEng, current, reason, ignored, pending, staged>>

\* Stale work stops at its next step and changes nothing; a stale pick's crosshair closes.
StaleWorkEndsOf(i) ==
    /\ tasks[i].stage \notin {"done"} /\ ~Live(i)
    /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, chosen, loadedEng, current, shown, reason, ignored, pending, staged>>

DownloadFinishes == \E i \in Ids : DownloadFinishesOf(i)
DownloadFails == \E i \in Ids : DownloadFailsOf(i)
LoadFinishes == \E i \in Ids : LoadFinishesOf(i)
YouDragAnArea == \E i \in Ids : YouDragAnAreaOf(i)
YouPressEscape == \E i \in Ids : YouPressEscapeOf(i)
TextRecognized == \E i \in Ids : TextRecognizedOf(i)
TextRecognitionEmpty == \E i \in Ids : TextRecognitionEmptyOf(i)
PageEnds == \E i \in Ids : PageEndsOf(i)
SampleEnds == \E i \in Ids : SampleEndsOf(i)
ClipEnds == \E i \in Ids : ClipEndsOf(i)
StaleWorkEnds == \E i \in Ids : StaleWorkEndsOf(i)

Next ==
    \/ YouPressPlay \/ YouOpenArea \/ YouReadText \/ YouDropFile \/ YouStartStaged \/ YouClearStaged
    \/ YouPressStop \/ YouSkip \/ YouDownloadInSetup \/ YouChooseVoice
    \/ YouChooseVoiceWithoutClip \/ YouPreview
    \/ DownloadFinishes \/ DownloadFails \/ LoadFinishes \/ YouDragAnArea \/ YouPressEscape
    \/ TextRecognized \/ TextRecognitionEmpty \/ PageEnds \/ SampleEnds \/ ClipEnds \/ StaleWorkEnds

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
\* Every live file reading came from an explicit Read confirmation, never directly from a drop.
NoAutoReadOnDrop == \A i \in LiveReaders : tasks[i].src = "file" => tasks[i].deliberate
\* While OCR runs on a page or screen area, the player stays visible in the recognizing state.
FeedbackDuringOCR == \A i \in Ids : (Live(i) /\ tasks[i].stage = "ocr") => ui = "recognizing"
Bound == Len(tasks) <= MaxTasks
====

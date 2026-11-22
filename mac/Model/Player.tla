---- MODULE Player ----
\* Berang's player, Sources/Berang/Player.swift. Each request (press play, read an area, open a file, skip)
\* runs as a task that steps through stages; choosing a voice while nothing reads plays a sample in it, and a
\* voice's recorded preview plays without a download. A request replaces the work before it, replaced work changes
\* nothing, and a request made while the voice downloads or loads waits for it.
\* Check: java -cp tla2tools.jar tlc2.TLC -config Player.cfg Player.tla
EXTENDS Naturals, FiniteSets, Sequences
CONSTANTS MaxTasks

VARIABLES ui, voice, loaded, tasks, current, shown, reason, ignored, pending
vars == <<ui, voice, loaded, tasks, current, shown, reason, ignored, pending>>
Ids == 1..Len(tasks)

Init ==
    /\ ui = "idle" /\ voice \in {"missing", "installed"} /\ loaded = FALSE
    /\ tasks = <<>> /\ current = 0 /\ shown = "none" /\ reason = "none"
    /\ ignored = FALSE /\ pending = "none"

Set(i, f, v) == [tasks EXCEPT ![i][f] = v]
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
FirstStages(src) ==
    IF loaded THEN Ready(src)
    ELSE IF voice = "missing" THEN {<<"download", "downloading">>} ELSE {<<"load", "loading">>}

\* begin(): cancel the current work, then start this request.
Begin(src) ==
    \E st \in FirstStages(src) :
        /\ tasks' = Append(Cancelled(tasks), [src |-> src, stage |-> st[1], cancelled |-> FALSE])
        /\ current' = Len(tasks) + 1 /\ ui' = st[2]
        /\ shown' = IF st[1] = "read" THEN src ELSE "none"

YouPressPlay ==
    /\ UNCHANGED <<voice, loaded, reason, ignored>>
    /\ \/ ui = "playing" /\ ui' = "paused" /\ UNCHANGED <<tasks, current, shown, pending>>
       \/ ui = "paused" /\ ui' = "playing" /\ UNCHANGED <<tasks, current, shown, pending>>
       \/ ui \in {"idle", "failed"} /\ Begin("window") /\ UNCHANGED pending
       \/ Preparing /\ pending' = "window" /\ UNCHANGED <<ui, tasks, current, shown>>

YouOpen(src) ==
    /\ UNCHANGED <<voice, loaded, reason, ignored>>
    /\ \/ Preparing /\ pending' = src /\ UNCHANGED <<ui, tasks, current, shown>>
       \/ ~Preparing /\ Begin(src) /\ UNCHANGED pending
YouOpenArea == YouOpen("area")
YouOpenFile == YouOpen("file")

YouPressStop ==
    /\ ui \in {"playing", "paused"}
    /\ tasks' = Cancelled(tasks) /\ ui' = "idle" /\ shown' = "none"
    /\ UNCHANGED <<current, voice, loaded, reason, ignored, pending>>

YouSkip ==
    /\ ui \in {"playing", "paused"} /\ current \in Ids
    /\ tasks' = Append(Cancelled(tasks), [src |-> tasks[current].src, stage |-> "read", cancelled |-> FALSE])
    /\ current' = Len(tasks) + 1 /\ ui' = "playing"
    /\ UNCHANGED <<shown, voice, loaded, reason, ignored, pending>>

\* choose(): while reading, the next sentence takes the voice, which changes no state here; otherwise a sample.
YouChooseVoice ==
    /\ ui \in {"idle", "failed"} /\ voice = "installed"
    /\ \E st \in FirstStages("sample") :
        /\ tasks' = Append(Cancelled(tasks), [src |-> "sample", stage |-> st[1], cancelled |-> FALSE])
        /\ current' = Len(tasks) + 1 /\ ui' = st[2] /\ shown' = "none"
    /\ UNCHANGED <<voice, loaded, reason, ignored, pending>>

\* choose() with a voice of the other engine: it must load first, so a reading stops and the sample waits for it.
YouChooseVoiceOfOtherEngine ==
    /\ ui \in {"idle", "failed", "playing", "paused"} /\ voice = "installed"
    /\ tasks' = Append(Cancelled(tasks), [src |-> "sample", stage |-> "load", cancelled |-> FALSE])
    /\ current' = Len(tasks) + 1 /\ ui' = "loading" /\ shown' = "none" /\ loaded' = FALSE
    /\ UNCHANGED <<voice, reason, ignored, pending>>

\* preview(): beside a download or load it plays alone; otherwise it replaces what plays.
YouPreview ==
    /\ \/ Preparing /\ tasks' = Append(Quiet(tasks), [src |-> "clip", stage |-> "clip", cancelled |-> FALSE])
          /\ UNCHANGED <<ui, current, shown>>
       \/ ~Preparing /\ tasks' = Append(Cancelled(tasks), [src |-> "clip", stage |-> "clip", cancelled |-> FALSE])
          /\ current' = Len(tasks) + 1 /\ ui' = "idle" /\ shown' = "none"
    /\ UNCHANGED <<voice, loaded, reason, ignored, pending>>

ClipEndsOf(i) ==
    /\ tasks[i].stage = "clip" /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, loaded, current, shown, reason, ignored, pending>>

YouDownloadInSetup ==
    /\ voice = "missing" /\ ui \in {"idle", "failed"}
    /\ tasks' = Append(Cancelled(tasks), [src |-> "setup", stage |-> "download", cancelled |-> FALSE])
    /\ current' = Len(tasks) + 1 /\ ui' = "downloading" /\ shown' = "none"
    /\ UNCHANGED <<voice, loaded, reason, ignored, pending>>

\* --- the current task's steps --------------------------------------------
Live(i) == i = current /\ ~tasks[i].cancelled

GoOn(i, src) ==   \* the voice is ready: run the latest request
    \E st \in Ready(src) :
        /\ tasks' = [Quiet(tasks) EXCEPT ![i] = [src |-> src, stage |-> st[1], cancelled |-> FALSE]]
        /\ ui' = st[2] /\ shown' = IF st[1] = "read" THEN src ELSE "none"

DownloadFinishesOf(i) ==
    /\ tasks[i].stage = "download" /\ Live(i) /\ voice' = "installed"
    /\ \/ tasks[i].src = "setup" /\ pending = "none"
          /\ tasks' = Set(i, "stage", "done") /\ ui' = "idle" /\ UNCHANGED <<shown, pending>>
       \/ (tasks[i].src # "setup" \/ pending # "none")
          /\ tasks' = [tasks EXCEPT ![i] = [@ EXCEPT !.stage = "load",
                                              !.src = IF pending # "none" THEN pending ELSE @]]
          /\ ui' = "loading" /\ pending' = "none" /\ UNCHANGED shown
    /\ UNCHANGED <<loaded, current, reason, ignored>>

DownloadFailsOf(i) ==
    /\ tasks[i].stage = "download" /\ Live(i)
    /\ tasks' = Set(i, "stage", "done") /\ ui' = "failed" /\ reason' = "network" /\ pending' = "none"
    /\ UNCHANGED <<voice, loaded, current, shown, ignored>>

LoadFinishesOf(i) ==
    /\ tasks[i].stage = "load" /\ Live(i) /\ loaded' = TRUE
    /\ GoOn(i, IF pending # "none" THEN pending ELSE tasks[i].src) /\ pending' = "none"
    /\ UNCHANGED <<voice, current, reason, ignored>>

YouDragAnAreaOf(i) ==
    /\ tasks[i].stage = "pick" /\ Live(i)
    /\ tasks' = Set(i, "stage", "read") /\ ui' = "playing" /\ shown' = "area"
    /\ UNCHANGED <<voice, loaded, current, reason, ignored, pending>>

YouPressEscapeOf(i) ==
    /\ tasks[i].stage = "pick" /\ Live(i) /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, loaded, current, shown, reason, ignored, pending>>

TextRecognizedOf(i) ==
    /\ tasks[i].stage = "ocr" /\ Live(i)
    /\ tasks' = Set(i, "stage", "read") /\ ui' = "playing" /\ shown' = "window"
    /\ UNCHANGED <<voice, loaded, current, reason, ignored, pending>>

SampleEndsOf(i) ==
    /\ tasks[i].stage = "sample" /\ Live(i) /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, loaded, current, shown, reason, ignored, pending>>

PageEndsOf(i) ==
    /\ tasks[i].stage = "read" /\ Live(i) /\ ui = "playing"
    /\ tasks' = Set(i, "stage", "done") /\ ui' = "idle" /\ shown' = "none"
    /\ UNCHANGED <<voice, loaded, current, reason, ignored, pending>>

\* Stale work stops at its next step and changes nothing; a stale pick's crosshair closes.
StaleWorkEndsOf(i) ==
    /\ tasks[i].stage \notin {"done"} /\ ~Live(i)
    /\ tasks' = Set(i, "stage", "done")
    /\ UNCHANGED <<ui, voice, loaded, current, shown, reason, ignored, pending>>

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
    \/ YouPressPlay \/ YouOpenArea \/ YouOpenFile \/ YouPressStop \/ YouSkip \/ YouDownloadInSetup \/ YouChooseVoice \/ YouChooseVoiceOfOtherEngine \/ YouPreview
    \/ DownloadFinishes \/ DownloadFails \/ LoadFinishes \/ YouDragAnArea \/ YouPressEscape
    \/ TextRecognized \/ PageEnds \/ SampleEnds \/ ClipEnds \/ StaleWorkEnds

Spec == Init /\ [][Next]_vars

LiveReaders == {i \in Ids : tasks[i].stage = "read" /\ ~tasks[i].cancelled}
\* Readings and samples both play sound.
OneThingAtATime == Cardinality({i \in Ids : tasks[i].stage \in {"read", "sample", "clip"} /\ ~tasks[i].cancelled}) <= 1
PlayingMeansSound == ui = "playing" => LiveReaders # {}
NoErrorFromStopping == reason # "cancelled"
NoIgnoredRequest == ~ignored
FollowsWhatYouHear == \A i \in LiveReaders : shown = tasks[i].src
\* A request made while the voice gets ready is read once it is ready, or the failure says why.
PendingOnlyWhilePreparing == pending # "none" => Preparing
Bound == Len(tasks) <= MaxTasks
====

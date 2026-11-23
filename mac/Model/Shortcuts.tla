---- MODULE Shortcuts ----
\* Changing Berang's global shortcuts, Sources/Berang/Shortcuts.swift.
\*
\* Berang has two shortcuts, read the page and read a screen area. In Settings you record a new key combination for
\* either. macOS lets several apps register one combination, and a press goes to the app that registered it last.
\* So registering never fails because another app holds a combination: Berang would take it from that app. Instead,
\* while you record, Berang watches the keyboard. A press it sees there but never receives went to macOS or another
\* app, and Berang refuses it. It also refuses the other shortcut's combination and the ones macOS lists as its own.
\*
\* Other apps register and drop combinations at any moment, also while Berang is quit. One that registers Berang's
\* combination later takes its presses, which Berang can't see; Settings then still shows the shortcut as working.
\*
\* While you record, pressing a combination Berang holds records it instead of starting to read.
\*
\* With SafeOrder = TRUE, a change registers the new combination first and lets go of the old one once the new one
\* works. With SafeOrder = FALSE it lets go of the old one first, and a failed registration leaves no shortcut. With
\* Watch = FALSE, Berang doesn't watch the keyboard while recording and accepts whatever it is told, and TLC finds it
\* saving a combination that another app was receiving.
\* Check: java -cp tla2tools.jar tlc2.TLC -config Shortcuts.cfg Shortcuts.tla
EXTENDS Naturals, FiniteSets
CONSTANTS SafeOrder, Watch

Actions == {"page", "area"}
Combos == {"optEsc", "optShiftEsc", "c3", "c4"}
System == {"c4"}                       \* macOS's own, such as ⌘ Space for Spotlight
Default == [a \in Actions |-> IF a = "page" THEN "optEsc" ELSE "optShiftEsc"]
None == "none"

VARIABLES running, held, saved, others, last, recording, step, wanted, status, note, reading, stolen
vars == <<running, held, saved, others, last, recording, step, wanted, status, note, reading, stolen>>

\* held[a]: the combinations Berang holds for action a; two only for a moment during a change.
\* others: combinations other apps hold. last[c]: who registered c last, and so gets its presses.
\* stolen: whether Berang went on with a combination that was going to another app when you pressed it. Another app
\* registering it in the instant between your press and Berang's registration can't be seen, so isn't counted.
HeldByBerang == UNION {held[a] : a \in Actions}
ReachesBerang(c) == c \in HeldByBerang /\ last[c] = "berang"
TakenElsewhere(c) == c \in System \/ (c \in others /\ last[c] = "other")

Init ==
    /\ running = TRUE /\ saved = Default /\ others \in SUBSET (Combos \ System)
    /\ held = [a \in Actions |-> {Default[a]}]
    /\ last = [c \in Combos |-> IF \E a \in Actions : Default[a] = c THEN "berang" ELSE IF c \in others THEN "other" ELSE "none"]
    /\ recording = None /\ step = "idle" /\ wanted = None /\ reading = FALSE /\ stolen = FALSE
    /\ status = [a \in Actions |-> "working"] /\ note = [a \in Actions |-> "none"]

Other(a) == CHOOSE b \in Actions : b # a
Keep == <<running, held, saved, recording, step, wanted, status, note, reading, stolen>>

OtherAppRegisters ==
    \E c \in Combos \ System :
        /\ others' = others \cup {c} /\ last' = [last EXCEPT ![c] = "other"]
        /\ UNCHANGED Keep
OtherAppDrops ==
    \E c \in others :
        /\ others' = others \ {c}
        /\ last' = [last EXCEPT ![c] = IF c \in HeldByBerang THEN "berang" ELSE "none"]
        /\ UNCHANGED Keep

YouStartRecording ==
    \E a \in Actions :
        /\ running /\ recording = None /\ step = "idle"
        /\ recording' = a
        /\ UNCHANGED <<running, held, saved, others, last, step, wanted, status, note, reading, stolen>>

YouCancelRecording ==
    /\ recording # None /\ step = "idle" /\ recording' = None
    /\ UNCHANGED <<running, held, saved, others, last, step, wanted, status, note, reading, stolen>>

\* A press of a combination Berang receives: while recording it is what you recorded; otherwise it reads.
YouPressAShortcut ==
    \E a \in Actions : \E c \in held[a] :
        /\ running /\ step = "idle" /\ ReachesBerang(c)
        /\ IF recording = None
           THEN reading' = TRUE /\ UNCHANGED <<recording, wanted, step>>
           ELSE wanted' = c /\ step' = "check" /\ UNCHANGED <<recording, reading>>
        /\ UNCHANGED <<running, held, saved, others, last, status, note, stolen>>

\* Any other combination, typed while recording. One that macOS or another app takes never reaches Berang; only the
\* keyboard watcher sees it. Without the watcher, assume the worst: Berang is told of it anyway and treats it as free.
YouTypeACombination ==
    \E c \in Combos :
        /\ recording # None /\ step = "idle" /\ ~ReachesBerang(c)
        /\ IF TakenElsewhere(c) /\ Watch
           THEN /\ note' = [note EXCEPT ![recording] = "used by macOS or another app"]
                /\ UNCHANGED <<wanted, step>>
           ELSE wanted' = c /\ step' = "check" /\ UNCHANGED note
        /\ stolen' = (stolen \/ (wanted' = c /\ TakenElsewhere(c)))
        /\ UNCHANGED <<running, held, saved, others, last, recording, status, reading>>

Check ==
    LET a == recording IN
    /\ step = "check"
    /\ CASE wanted \in held[a] ->
               (step' = "idle" /\ recording' = None /\ wanted' = None
                /\ note' = [note EXCEPT ![a] = "none"] /\ UNCHANGED <<held, status>>)
         [] wanted \in held[Other(a)] \/ wanted = saved[Other(a)] ->
               (step' = "idle" /\ wanted' = None /\ note' = [note EXCEPT ![a] = "used by the other shortcut"]
                /\ UNCHANGED <<held, recording, status>>)
         [] wanted \in System ->
               (step' = "idle" /\ wanted' = None /\ note' = [note EXCEPT ![a] = "used by macOS"]
                /\ UNCHANGED <<held, recording, status>>)
         [] OTHER ->
               (step' = (IF SafeOrder THEN "register" ELSE "release") /\ UNCHANGED <<held, recording, wanted, status, note>>)
    /\ UNCHANGED <<running, saved, others, last, reading, stolen>>

Release ==
    /\ step = "release" /\ held' = [held EXCEPT ![recording] = {}] /\ step' = "register"
    /\ UNCHANGED <<running, saved, others, last, recording, wanted, status, note, reading, stolen>>

\* Registration succeeds even over another app, taking its presses; it can still fail for other reasons.
Register ==
    LET a == recording IN
    /\ step = "register"
    /\ \/ /\ held' = [held EXCEPT ![a] = @ \cup {wanted}] /\ last' = [last EXCEPT ![wanted] = "berang"]
          /\ step' = "commit" /\ UNCHANGED <<status, note, wanted, stolen>>
       \/ /\ UNCHANGED <<held, last, stolen>>
          /\ note' = [note EXCEPT ![a] = "couldn't be registered"]
          /\ status' = (IF held[a] = {} THEN [status EXCEPT ![a] = "unavailable"] ELSE status)
          /\ step' = "idle" /\ wanted' = None
    /\ UNCHANGED <<running, saved, others, recording, reading>>

Commit ==
    LET a == recording IN
    /\ step = "commit"
    /\ held' = [held EXCEPT ![a] = {wanted}]
    /\ last' = [c \in Combos |-> IF c \in held[a] /\ c # wanted /\ last[c] = "berang"
                                 THEN (IF c \in others THEN "other" ELSE "none") ELSE last[c]]
    /\ saved' = [saved EXCEPT ![a] = wanted]
    /\ status' = [status EXCEPT ![a] = "working"] /\ note' = [note EXCEPT ![a] = "none"]
    /\ step' = "idle" /\ recording' = None /\ wanted' = None
    /\ UNCHANGED <<running, others, reading, stolen>>

YouStopReading ==
    /\ reading /\ reading' = FALSE
    /\ UNCHANGED <<running, held, saved, others, last, recording, step, wanted, status, note, stolen>>

YouQuit ==
    /\ running /\ step = "idle"
    /\ running' = FALSE /\ held' = [a \in Actions |-> {}] /\ recording' = None /\ reading' = FALSE
    /\ last' = [c \in Combos |-> IF last[c] = "berang" THEN (IF c \in others THEN "other" ELSE "none") ELSE last[c]]
    /\ UNCHANGED <<saved, others, step, wanted, status, note, stolen>>

\* At launch Berang registers its saved combinations, which then reach it, even over another app.
YouOpen ==
    /\ ~running /\ running' = TRUE
    /\ held' = [a \in Actions |-> {saved[a]}]
    /\ last' = [c \in Combos |-> IF \E a \in Actions : saved[a] = c THEN "berang" ELSE last[c]]
    /\ status' = [a \in Actions |-> "working"] /\ note' = [a \in Actions |-> "none"]
    /\ UNCHANGED <<saved, others, recording, step, wanted, reading, stolen>>

Next ==
    \/ OtherAppRegisters \/ OtherAppDrops \/ YouStartRecording \/ YouCancelRecording \/ YouPressAShortcut
    \/ YouTypeACombination \/ Check \/ Release \/ Register \/ Commit \/ YouStopReading \/ YouQuit \/ YouOpen

\* A change that fails leaves a working shortcut working.
KeptOnFailure == [][step = "register" /\ step' = "idle" /\ status[recording] = "working" => status'[recording] = "working"]_vars
\* Settings never shows a shortcut as working while Berang holds nothing for it.
NeverLost == running /\ step = "idle" => \A a \in Actions : status[a] = "working" => held[a] # {}
\* What Berang holds is what it saved, so the next launch registers the same combinations.
HeldIsSaved == running /\ step = "idle" => \A a \in Actions : held[a] \subseteq {saved[a]}
\* The two shortcuts never share a combination, and neither takes one macOS keeps.
Distinct == saved["page"] # saved["area"] /\ \A a \in Actions : saved[a] \notin System
\* Berang never takes a combination that went to another app when you pressed it.
NoStealing == ~stolen
\* Recording a shortcut never starts a reading.
NoReadingFromRecording == [][recording # None /\ ~reading => ~reading']_vars
====

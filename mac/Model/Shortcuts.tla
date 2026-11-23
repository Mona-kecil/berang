---- MODULE Shortcuts ----
\* Changing Berang's global shortcuts, Sources/Berang/Shortcuts.swift.
\*
\* Berang has four shortcuts. Read the page and read a screen area work at any time. Faster and slower change the
\* speed, and Berang holds them only while the player shows, so the rest of the time those keys go to the app in
\* front, where ⌥ ⇧ . types "˘". In Settings you record a new key combination for any of them.
\*
\* macOS lets several apps register one combination, and a press goes to the app that registered it last. So
\* registering never fails because another app holds a combination: Berang would take it from that app. Instead,
\* while you record, Berang watches the keyboard. A press it sees there but never receives went to macOS or another
\* app, and Berang refuses it. It also refuses another shortcut's combination and the ones macOS lists as its own.
\*
\* Other apps register and drop combinations at any moment, also while Berang is quit or not reading. One that
\* registers Berang's combination later takes its presses, which Berang can't see, until Berang registers it again,
\* at launch or when reading starts; Settings still shows the shortcut as working.
\*
\* While you record, pressing a combination Berang holds records it instead of reading or changing the speed.
\*
\* Everything here runs on the main thread, so reading starts and stops only between changes, never during one.
\*
\* With SafeOrder = TRUE, a change registers the new combination first and lets go of the old one once the new one
\* works. With SafeOrder = FALSE it lets go of the old one first, and a failed registration leaves no shortcut. With
\* Watch = FALSE, Berang doesn't watch the keyboard while recording and accepts whatever it is told, and TLC finds it
\* saving a combination that another app was receiving. With Release = FALSE, a speed shortcut recorded while not
\* reading stays registered, and TLC finds Berang holding it with the player closed.
\* Check: java -cp tla2tools.jar tlc2.TLC -config Shortcuts.cfg Shortcuts.tla
EXTENDS Naturals, FiniteSets
CONSTANTS SafeOrder, Watch, Release
\* Always and WhileReading name the shortcuts of each kind; the checks use fewer than Berang has, as the two speed
\* shortcuts behave alike.
CONSTANTS Always, WhileReading

Actions == Always \cup WhileReading
Default == [a \in Actions |-> CASE a = "page" -> "optEsc" [] a = "area" -> "optShiftEsc"
                                [] a = "faster" -> "optShiftDot" [] OTHER -> "optShiftComma"]
System == {"sys"}                      \* macOS's own, such as ⌘ Space for Spotlight
Combos == {Default[a] : a \in Actions} \cup {"free"} \cup System
None == "none"

VARIABLES running, held, saved, others, last, recording, step, wanted, status, note, reading, stolen, byKeys
vars == <<running, held, saved, others, last, recording, step, wanted, status, note, reading, stolen, byKeys>>

\* held[a]: the combinations Berang holds for action a; two only for a moment during a change.
\* others: combinations other apps hold. last[c]: who registered c last, and so gets its presses.
\* reading: whether the player shows, from a press of read the page until reading stops.
\* stolen: whether Berang went on with a combination that was going to another app when you pressed it. Another app
\* registering it in the instant between your press and Berang's registration can't be seen, so isn't counted.
\* byKeys: whether the last step was a shortcut press that read or changed the speed.
HeldByBerang == UNION {held[a] : a \in Actions}
ReachesBerang(c) == c \in HeldByBerang /\ last[c] = "berang"
TakenElsewhere(c) == c \in System \/ (c \in others /\ last[c] = "other")
\* Who gets c's presses once Berang lets go of it.
Freed(c) == IF c \in others THEN "other" ELSE "none"

Init ==
    /\ running = TRUE /\ saved = Default /\ others \in SUBSET (Combos \ System)
    /\ held = [a \in Actions |-> IF a \in Always THEN {Default[a]} ELSE {}]
    /\ last = [c \in Combos |-> IF \E a \in Always : Default[a] = c THEN "berang" ELSE IF c \in others THEN "other" ELSE "none"]
    /\ recording = None /\ step = "idle" /\ wanted = None /\ reading = FALSE /\ stolen = FALSE /\ byKeys = FALSE
    /\ status = [a \in Actions |-> "working"] /\ note = [a \in Actions |-> "none"]

Keep == <<running, held, saved, recording, step, wanted, status, note, reading, stolen>>

OtherAppRegisters ==
    \E c \in Combos \ System :
        /\ others' = others \cup {c} /\ last' = [last EXCEPT ![c] = "other"]
        /\ byKeys' = FALSE /\ UNCHANGED Keep
OtherAppDrops ==
    \E c \in others :
        /\ others' = others \ {c}
        /\ last' = [last EXCEPT ![c] = IF c \in HeldByBerang THEN "berang" ELSE "none"]
        /\ byKeys' = FALSE /\ UNCHANGED Keep

\* Reading starts and Berang registers the speed shortcuts, even over another app. Those in ok succeed.
StartsReading ==
    \E ok \in SUBSET WhileReading :
        /\ reading' = TRUE
        /\ held' = [a \in Actions |-> IF a \in WhileReading THEN (IF a \in ok THEN {saved[a]} ELSE {}) ELSE held[a]]
        /\ last' = [c \in Combos |-> IF \E a \in ok : saved[a] = c THEN "berang" ELSE last[c]]
        /\ status' = [a \in Actions |-> IF a \in ok THEN "working" ELSE IF a \in WhileReading THEN "unavailable" ELSE status[a]]
        /\ note' = [a \in Actions |-> IF a \in WhileReading \ ok THEN "couldn't be registered" ELSE note[a]]

\* Reading stops, from the player or at the end, and Berang lets go of the speed shortcuts.
StopsReading ==
    /\ reading' = FALSE
    /\ held' = [a \in Actions |-> IF a \in WhileReading THEN {} ELSE held[a]]
    /\ last' = [c \in Combos |-> IF (\E a \in WhileReading : c \in held[a]) /\ last[c] = "berang" THEN Freed(c) ELSE last[c]]

YouStartRecording ==
    \E a \in Actions :
        /\ running /\ recording = None /\ step = "idle"
        /\ recording' = a /\ byKeys' = FALSE
        /\ UNCHANGED <<running, held, saved, others, last, step, wanted, status, note, reading, stolen>>

YouCancelRecording ==
    /\ recording # None /\ step = "idle" /\ recording' = None /\ byKeys' = FALSE
    /\ UNCHANGED <<running, held, saved, others, last, step, wanted, status, note, reading, stolen>>

\* A press of a combination Berang receives. While recording it is what you recorded. Otherwise read the page or
\* read an area starts reading, or pauses or resumes it, and faster or slower changes the speed.
YouPressAShortcut ==
    \E a \in Actions : \E c \in held[a] :
        /\ running /\ step = "idle" /\ ReachesBerang(c)
        /\ IF recording # None
           THEN /\ wanted' = c /\ step' = "check" /\ byKeys' = FALSE
                /\ UNCHANGED <<held, last, status, note, reading>>
           ELSE /\ byKeys' = TRUE /\ UNCHANGED <<wanted, step>>
                /\ IF a \in Always /\ ~reading THEN StartsReading ELSE UNCHANGED <<held, last, status, note, reading>>
        /\ UNCHANGED <<running, saved, others, recording, stolen>>

\* Reading started from the menu bar, the Voices page, or a file opened with Berang.
YouReadFromElsewhere ==
    /\ running /\ ~reading /\ step = "idle" /\ StartsReading /\ byKeys' = FALSE
    /\ UNCHANGED <<running, saved, others, recording, step, wanted, stolen>>

YouStopReading ==
    /\ reading /\ step = "idle" /\ StopsReading /\ byKeys' = FALSE
    /\ UNCHANGED <<running, saved, others, recording, step, wanted, status, note, stolen>>

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
        /\ byKeys' = FALSE
        /\ UNCHANGED <<running, held, saved, others, last, recording, status, reading>>

Check ==
    LET a == recording IN
    /\ step = "check"
    /\ CASE wanted \in held[a] \/ (wanted = saved[a] /\ status[a] = "working") ->
               (step' = "idle" /\ recording' = None /\ wanted' = None
                /\ note' = [note EXCEPT ![a] = "none"] /\ UNCHANGED <<held, status>>)
         [] \E b \in Actions \ {a} : wanted \in held[b] \/ wanted = saved[b] ->
               (step' = "idle" /\ wanted' = None /\ note' = [note EXCEPT ![a] = "used by another shortcut"]
                /\ UNCHANGED <<held, recording, status>>)
         [] wanted \in System ->
               (step' = "idle" /\ wanted' = None /\ note' = [note EXCEPT ![a] = "used by macOS"]
                /\ UNCHANGED <<held, recording, status>>)
         [] OTHER ->
               (step' = (IF SafeOrder THEN "register" ELSE "release") /\ UNCHANGED <<held, recording, wanted, status, note>>)
    /\ byKeys' = FALSE
    /\ UNCHANGED <<running, saved, others, last, reading, stolen>>

ReleaseOld ==
    /\ step = "release" /\ held' = [held EXCEPT ![recording] = {}] /\ step' = "register" /\ byKeys' = FALSE
    /\ UNCHANGED <<running, saved, others, last, recording, wanted, status, note, reading, stolen>>

\* Registration succeeds even over another app, taking its presses; it can still fail for other reasons. A speed
\* shortcut recorded while not reading is registered too, to learn whether it can be, and let go at Commit.
Register ==
    LET a == recording IN
    /\ step = "register"
    /\ \/ /\ held' = [held EXCEPT ![a] = @ \cup {wanted}] /\ last' = [last EXCEPT ![wanted] = "berang"]
          /\ step' = "commit" /\ UNCHANGED <<status, note, wanted, stolen>>
       \/ /\ UNCHANGED <<held, last, stolen>>
          /\ note' = [note EXCEPT ![a] = "couldn't be registered"]
          /\ status' = (IF held[a] = {} /\ (a \in Always \/ reading) THEN [status EXCEPT ![a] = "unavailable"] ELSE status)
          /\ step' = "idle" /\ wanted' = None
    /\ byKeys' = FALSE
    /\ UNCHANGED <<running, saved, others, recording, reading>>

Commit ==
    LET a == recording
        kept == IF a \in WhileReading /\ ~reading /\ Release THEN {} ELSE {wanted}
    IN
    /\ step = "commit"
    /\ held' = [held EXCEPT ![a] = kept]
    /\ last' = [c \in Combos |-> IF c \in held[a] \ kept /\ last[c] = "berang" THEN Freed(c) ELSE last[c]]
    /\ saved' = [saved EXCEPT ![a] = wanted]
    /\ status' = [status EXCEPT ![a] = "working"] /\ note' = [note EXCEPT ![a] = "none"]
    /\ step' = "idle" /\ recording' = None /\ wanted' = None /\ byKeys' = FALSE
    /\ UNCHANGED <<running, others, reading, stolen>>

YouQuit ==
    /\ running /\ step = "idle"
    /\ running' = FALSE /\ held' = [a \in Actions |-> {}] /\ recording' = None /\ reading' = FALSE /\ byKeys' = FALSE
    /\ last' = [c \in Combos |-> IF last[c] = "berang" THEN Freed(c) ELSE last[c]]
    /\ UNCHANGED <<saved, others, step, wanted, status, note, stolen>>

\* At launch Berang registers its saved always-on combinations, which then reach it, even over another app.
YouOpen ==
    /\ ~running /\ running' = TRUE /\ byKeys' = FALSE
    /\ held' = [a \in Actions |-> IF a \in Always THEN {saved[a]} ELSE {}]
    /\ last' = [c \in Combos |-> IF \E a \in Always : saved[a] = c THEN "berang" ELSE last[c]]
    /\ status' = [a \in Actions |-> "working"] /\ note' = [a \in Actions |-> "none"]
    /\ UNCHANGED <<saved, others, recording, step, wanted, reading, stolen>>

Next ==
    \/ OtherAppRegisters \/ OtherAppDrops \/ YouStartRecording \/ YouCancelRecording \/ YouPressAShortcut
    \/ YouReadFromElsewhere \/ YouStopReading \/ YouTypeACombination \/ Check \/ ReleaseOld \/ Register \/ Commit
    \/ YouQuit \/ YouOpen

\* A change that fails leaves a working shortcut working.
KeptOnFailure == [][step = "register" /\ step' = "idle" /\ status[recording] = "working" => status'[recording] = "working"]_vars
\* Settings never shows a shortcut as working while Berang holds nothing for it at a time it should.
NeverLost == running /\ step = "idle" =>
    \A a \in Actions : status[a] = "working" /\ (a \in Always \/ reading) => held[a] # {}
\* The speed shortcuts are held only while reading, so the rest of the time their keys reach the app in front.
SpeedKeysOnlyWhileReading == step = "idle" => \A a \in WhileReading : held[a] # {} => reading
\* What Berang holds is what it saved, so the next launch or reading registers the same combinations.
HeldIsSaved == running /\ step = "idle" => \A a \in Actions : held[a] \subseteq {saved[a]}
\* No two shortcuts share a combination, held or not, and none takes one macOS keeps.
Distinct == \A a, b \in Actions : a # b => saved[a] # saved[b] /\ saved[a] \notin System
\* Berang never takes a combination that went to another app when you pressed it.
NoStealing == ~stolen
\* Recording a shortcut never starts a reading or changes the speed.
NoActingWhileRecording == [][recording # None => ~byKeys']_vars
====

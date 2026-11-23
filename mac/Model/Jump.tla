---- MODULE Jump ----
\* Reading from your selection, while Berang reads: select text in the page being read and press the read shortcut.
\* Sources/Berang/Player.swift, readOrPause.
\*
\* Berang reads a copy of one page, taken when reading started. While it reads, the read shortcut pauses or resumes,
\* unless you have selected text in that page since reading started or last moved: then reading moves to the
\* selection. A click, or a selection alone, never moves reading.
\*
\* At the press, Berang asks the page it is reading, not the window in front, for its selection, and finds the block
\* it starts in among its copy's. A page that changed, by a followed link or in another tab, has elements the copy
\* doesn't, so its selection is in none of the copy's blocks. Berang keeps the selection it last saw: the one there
\* when reading started, or the one it moved to. A selection equal to that one is not new, and the press pauses.
\* All of this happens at the press, on the main thread, so nothing changes in between.
\*
\* With Remember = FALSE, Berang doesn't keep the selection it saw, and TLC finds a press meant to pause moving
\* reading back to an old selection instead. With AskReadPage = FALSE, Berang asks the window in front, and TLC
\* finds it moving reading to a selection made in another page.
\* Check: java -cp tla2tools.jar tlc2.TLC -config Jump.cfg Jump.tla
EXTENDS Naturals
CONSTANTS Remember, AskReadPage, Blocks, MaxSelections, MaxMoves, MaxVersions

Windows == {"read", "other"}             \* the window being read, and any other window or tab
None == [id |-> 0]

VARIABLES state, at, front, version, copy, sel, seen, made, moves, wrong, jumped
vars == <<state, at, front, version, copy, sel, seen, made, moves, wrong, jumped>>

\* state: "idle", "playing" or "paused". at: the block being read. front: the window in front.
\* version: the read window's page now; copy: its page when reading started.
\* sel[w]: the selection in window w: an id, the block it starts in, the page version it was made on, and the move
\* it was made after. seen: the id of the selection Berang last saw. made: selections made so far.
\* moves: readings started plus jumps; a selection made since the last is new. wrong: why reading ever moved when
\* it shouldn't have. jumped: whether the last step moved reading to a selection.
Init ==
    /\ state = "idle" /\ at \in Blocks /\ front = "read" /\ version = 0 /\ copy = 0
    /\ sel = [w \in Windows |-> None] /\ seen = 0 /\ made = 0 /\ moves = 0 /\ wrong = {} /\ jumped = FALSE

\* The selection in the page being read, if it is in one of the copy's blocks.
InCopy == IF sel["read"] # None /\ sel["read"].version = copy /\ version = copy THEN sel["read"] ELSE None
\* What Berang finds when it asks.
Asked == IF AskReadPage THEN InCopy ELSE sel[front]

\* Reading starts, from the window in front, a file, or an area. Berang keeps the selection it finds in the page.
Start ==
    /\ state = "idle" /\ moves < MaxMoves
    /\ state' = "playing" /\ at' \in Blocks /\ copy' = version /\ moves' = moves + 1
    /\ seen' = IF Remember /\ sel["read"] # None /\ sel["read"].version = version THEN sel["read"].id ELSE 0
    /\ jumped' = FALSE
    /\ UNCHANGED <<front, version, sel, made, wrong>>

ReadOn ==
    /\ state = "playing"
    /\ IF at + 1 \in Blocks THEN at' = at + 1 /\ UNCHANGED state ELSE state' = "idle" /\ UNCHANGED at
    /\ jumped' = FALSE /\ UNCHANGED <<front, version, copy, sel, seen, made, moves, wrong>>

\* The player's play button and ✕.
PlayerButtons ==
    /\ state # "idle"
    /\ state' \in {"idle", IF state = "playing" THEN "paused" ELSE "playing"}
    /\ jumped' = FALSE /\ UNCHANGED <<at, front, version, copy, sel, seen, made, moves, wrong>>

SwitchWindow ==
    /\ front' \in Windows \ {front}
    /\ jumped' = FALSE /\ UNCHANGED <<state, at, version, copy, sel, seen, made, moves, wrong>>

\* A followed link or an edit. The read window's selection stays as it was made, on the page before.
PageChanges ==
    /\ version + 1 < MaxVersions /\ version' = version + 1
    /\ jumped' = FALSE /\ UNCHANGED <<state, at, front, copy, sel, seen, made, moves, wrong>>

YouSelect ==
    \E b \in Blocks :
        /\ made < MaxSelections /\ made' = made + 1
        /\ sel' = [sel EXCEPT ![front] = [id |-> made + 1, block |-> b, version |-> IF front = "read" THEN version ELSE MaxVersions, after |-> moves]]
        /\ jumped' = FALSE /\ UNCHANGED <<state, at, front, version, copy, seen, moves, wrong>>

YouClearASelection ==
    /\ sel[front] # None /\ sel' = [sel EXCEPT ![front] = None]
    /\ jumped' = FALSE /\ UNCHANGED <<state, at, front, version, copy, seen, made, moves, wrong>>

\* The read shortcut while reading: to a new selection in the page being read, or else pause or resume.
YouPressTheShortcut ==
    LET s == Asked IN
    /\ state # "idle"
    /\ IF s # None /\ s.id # seen /\ moves < MaxMoves
       THEN /\ at' = s.block /\ state' = "playing" /\ moves' = moves + 1 /\ jumped' = TRUE
            /\ seen' = IF Remember THEN s.id ELSE seen
            /\ wrong' = wrong \cup (IF s.after < moves THEN {"old selection"} ELSE {})
                              \cup (IF s.version # copy \/ version # copy THEN {"another page"} ELSE {})
       ELSE /\ state' = (IF state = "playing" THEN "paused" ELSE "playing") /\ jumped' = FALSE
            /\ UNCHANGED <<at, moves, seen, wrong>>
    /\ UNCHANGED <<front, version, copy, sel, made>>

\* The bounds are reached.
Done == state = "idle" /\ moves = MaxMoves /\ UNCHANGED vars

Next == Start \/ ReadOn \/ PlayerButtons \/ SwitchWindow \/ PageChanges \/ YouSelect \/ YouClearASelection
        \/ YouPressTheShortcut \/ Done

\* Reading moves only to a selection made since reading started or last moved, so a press meant to pause pauses.
NeverToAnOldSelection == "old selection" \notin wrong
\* Reading moves only within the page being read, as Berang copied it.
NeverToAnotherPage == "another page" \notin wrong
\* Only the shortcut moves reading: no click, selection, or switch of window does.
OnlyThePressMoves == [][jumped' => state # "idle" /\ at' = Asked.block]_vars
====

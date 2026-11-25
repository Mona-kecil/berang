---- MODULE Place ----
\* Where the floating player sits, kept across readings and launches. Sources/Berang/PlayerPanel.swift.
\*
\* The player rests against the left or right edge of a screen. You drag it anywhere; when you let go, it snaps to
\* the nearer edge of the screen you dropped it on, at the height you dropped it. Berang saves that spot as a screen,
\* an edge, and a height on that screen, so rearranging screens doesn't move it. Screens connect and disconnect at
\* any time, also while the player is hidden or Berang is quit. When a screen goes away, macOS moves the player onto
\* one that remains, and Berang hears of that move like any other. When the screen comes back, Berang moves the
\* player back to your spot. Each time the player shows, and whenever screens change, Berang puts it at your spot, or
\* at the right edge of the main screen, here the laptop's, while your spot's screen is gone.
\*
\* Berang saves the spot only when you drag the player. With SaveOnAnyMove = TRUE it saves every move, and TLC finds
\* the spot you chose lost after unplugging a screen.
\* Check: java -cp tla2tools.jar tlc2.TLC -config Place.cfg Place.tla
CONSTANTS SaveOnAnyMove

Screens == {"laptop", "external"}
\* Where you can leave the player: an edge of a screen, at some height. One height per edge covers the rest.
Spots == {"laptopRight", "laptopLeft", "externalRight", "externalLeft"}
\* Where macOS can also put it, when the screen it was on goes away: anywhere on the laptop's screen.
Places == Spots \cup {"laptopElsewhere"}
ScreenOf(s) == IF s \in {"laptopRight", "laptopLeft", "laptopElsewhere"} THEN "laptop" ELSE "external"
Default == "laptopRight"
None == "none"

VARIABLES connected, running, shown, at, saved, chosen
vars == <<connected, running, shown, at, saved, chosen>>

\* at: where the player is, shown or not. saved: the spot Berang keeps. chosen: the last spot you dragged it to.
Init ==
    /\ connected \in {{"laptop"}, Screens} /\ running = TRUE /\ shown = FALSE
    /\ at = Default /\ saved = None /\ chosen = None

\* Where the player goes when it shows: your spot, if its screen is there.
Place == IF saved # None /\ ScreenOf(saved) \in connected THEN saved ELSE Default

YouDrag ==
    \E s \in Spots :
        /\ running /\ shown /\ ScreenOf(s) \in connected
        /\ at' = s /\ saved' = s /\ chosen' = s
        /\ UNCHANGED <<connected, running, shown>>

ReadingStarts ==
    /\ running /\ ~shown /\ shown' = TRUE /\ at' = Place
    /\ UNCHANGED <<connected, running, saved, chosen>>

ReadingStops ==
    /\ shown /\ shown' = FALSE
    /\ UNCHANGED <<connected, running, at, saved, chosen>>

\* macOS moves a shown player off a screen that goes away, to somewhere on the laptop's.
Unplug ==
    /\ "external" \in connected /\ connected' = {"laptop"}
    /\ IF running /\ shown /\ ScreenOf(at) = "external"
       THEN \E s \in Places :
                /\ ScreenOf(s) = "laptop" /\ at' = s
                /\ saved' = IF SaveOnAnyMove THEN s ELSE saved
       ELSE UNCHANGED <<at, saved>>
    /\ UNCHANGED <<running, shown, chosen>>

\* Berang hears that the screens changed and puts a shown player back at your spot.
Plug ==
    /\ "external" \notin connected /\ connected' = Screens
    /\ at' = IF running /\ shown THEN (IF saved # None THEN saved ELSE at) ELSE at
    /\ UNCHANGED <<running, shown, saved, chosen>>

Quit ==
    /\ running /\ running' = FALSE /\ shown' = FALSE
    /\ UNCHANGED <<connected, at, saved, chosen>>

Open ==
    /\ ~running /\ running' = TRUE
    /\ UNCHANGED <<connected, shown, at, saved, chosen>>

Next == YouDrag \/ ReadingStarts \/ ReadingStops \/ Unplug \/ Plug \/ Quit \/ Open

\* A shown player is always on a screen you have.
OnAScreen == running /\ shown => ScreenOf(at) \in connected
\* The spot Berang keeps is one you chose, never one macOS moved the player to.
SavedIsYours == saved \in {None, chosen}
\* Whenever your spot's screen is there, a shown player is at your spot.
AtYourSpot == running /\ shown /\ saved # None /\ ScreenOf(saved) \in connected => at = saved
====

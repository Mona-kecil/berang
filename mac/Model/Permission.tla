---- MODULE Permission ----
\* The guide that floats beside System Settings while you switch on a permission. Sources/Berang/PermissionGuide.swift.
\*
\* Clicking Allow, or reading before Berang may, opens System Settings at the permission's pane and shows the guide
\* beside it. Reading before Berang may also leaves a failure in the player. Berang checks once a second whether
\* Accessibility is on. Once it is, the guide closes, that failure clears, and Berang comes to the front so you land
\* back in its window. The guide also closes when you close it, and when System Settings has been gone for a moment. A new ask replaces the guide on screen, so there is never more than one. Screen Recording
\* has a guide too, but macOS reports it as on only after Berang reopens, so that guide ends with System Settings.
\*
\* System Settings can take longer to open than to be waited for once it has been shown, so a guide waits longer
\* before Berang has found Settings' window. Berang looks for the window about every 40 ms, far faster than anyone
\* closes it, so the model lets a look happen at any time while the window is open. What Berang has found (`beside`)
\* is kept apart from the window's real state (`settings`): asking again while Settings is open finds it at once.
\*
\* The guide closes only when the checks below hold. Each TRUE below is a safeguard; set one to FALSE and TLC finds
\* the rule it keeps broken:
\*   - CloseOnGrant = FALSE: the guide stays up after the check sees access on (NoStaleGuide), and Berang comes to
\*     the front at every check after (OncePerGrant, when it is the only invariant checked).
\*   - FrontOnlyIfAsked = FALSE: Berang comes to the front for a switch you turned on yourself (FrontOnlyAfterAsking).
\*   - ReplaceOldGuide = FALSE: asking for Screen Recording beside an Accessibility guide shows both (OneGuide).
\*   - WaitForLaunch = FALSE: the guide closes while System Settings is still opening (NotCutShort).
\*   - CloseWhenSettingsGone = FALSE: the guide hangs on after you close System Settings (NotStranded).
\*   - ObserveOnShow = FALSE: asking forgets that System Settings is already open, so the guide waits as long as
\*     for a window it never found (SeenOnShow).
\*   - ClearOnGrant = FALSE: the player keeps its failure after the check sees access on (NoStaleFailure).
\* Check: java -cp tla2tools.jar tlc2.TLC -config Permission.cfg -workers auto Permission.tla
EXTENDS Naturals, FiniteSets
CONSTANTS CloseOnGrant, FrontOnlyIfAsked, ReplaceOldGuide, WaitForLaunch, CloseWhenSettingsGone, ObserveOnShow,
          ClearOnGrant

Kinds == {"ax", "screen"}
\* Berang looks for System Settings' window at a steady rhythm; a tick is one look. The guide closes once Settings
\* has been missing for Grace ticks, or Launch ticks while Berang has not found its window yet.
Grace == 2
Launch == 4

VARIABLES on, seen, settings, beside, guides, gone, fronts, stolen, early, blind, failed, stale
vars == <<on, seen, settings, beside, guides, gone, fronts, stolen, early, blind, failed, stale>>

\* on: Accessibility's switch. seen: what Berang's last look at it found. settings: System Settings' window.
\* beside: Berang has found Settings' window for the guide on screen. guides: the guides on screen.
\* gone: ticks Settings has been missing while a guide shows. fronts: times Berang came to the front for the
\* current grant. stolen: Berang came to the front without being asked. early: a guide closed while Settings was
\* still opening. blind: a guide was shown while Settings was open, and did not find it. failed: the player shows
\* the failure of a reading that lacked Accessibility. stale: that failure outlasted the check that found
\* Accessibility on.
Init ==
    /\ on = FALSE /\ seen = FALSE /\ settings = "closed" /\ beside = FALSE /\ guides = {} /\ gone = 0
    /\ fronts = 0 /\ stolen = FALSE /\ early = FALSE /\ blind = FALSE /\ failed = FALSE /\ stale = FALSE

\* Allow in setup, the player's button, or reading before Berang may, which also fails the reading (`fails`). Berang
\* reads Accessibility fresh, and asks only while it is off. Screen Recording has no switch to read: Berang asks
\* when a reading needs it. Asking looks for Settings' window at once.
Ask(k, fails) ==
    /\ (k = "ax" => ~on)
    /\ (fails => k = "ax")
    /\ guides' = IF ReplaceOldGuide THEN {k} ELSE guides \cup {k}
    /\ settings' = IF settings = "closed" THEN "launching" ELSE settings
    /\ gone' = 0
    /\ seen' = IF k = "ax" THEN on ELSE seen
    /\ beside' = IF ObserveOnShow THEN settings = "open" ELSE FALSE
    /\ blind' = (blind \/ (settings = "open" /\ ~beside'))
    /\ failed' = (failed \/ fails)
    /\ UNCHANGED <<on, fronts, stolen, early, stale>>

\* System Settings finishes opening, or you open it yourself.
SettingsOpens ==
    /\ settings # "open" /\ settings' = "open" /\ gone' = 0
    /\ UNCHANGED <<on, seen, beside, guides, fronts, stolen, early, blind, failed, stale>>

YouCloseSettings ==
    /\ settings = "open" /\ settings' = "closed"
    /\ UNCHANGED <<on, seen, beside, guides, gone, fronts, stolen, early, blind, failed, stale>>

\* Switching it off starts a new grant.
YouSwitch ==
    /\ settings = "open" /\ on' = ~on
    /\ fronts' = IF on THEN 0 ELSE fronts
    /\ UNCHANGED <<seen, settings, beside, guides, gone, stolen, early, blind, failed, stale>>

YouCloseGuide ==
    \E k \in guides :
        /\ guides' = guides \ {k}
        /\ gone' = IF guides' = {} THEN 0 ELSE gone
        /\ UNCHANGED <<on, seen, settings, beside, fronts, stolen, early, blind, failed, stale>>

\* The player's failure ends: you dismiss it, read again, or press its button once access is on.
FailureEnds ==
    /\ failed /\ failed' = FALSE
    /\ UNCHANGED <<on, seen, settings, beside, guides, gone, fronts, stolen, early, blind, stale>>

\* Berang finds System Settings' window while a guide shows.
Look ==
    /\ guides # {} /\ settings = "open" /\ ~beside /\ beside' = TRUE
    /\ UNCHANGED <<on, seen, settings, guides, gone, fronts, stolen, early, blind, failed, stale>>

\* The once-a-second look at Accessibility. Seeing it on while a guide asked for it closes the guide, clears the
\* player's failure, and brings Berang to the front.
Check ==
    /\ seen' = on
    /\ IF on /\ ("ax" \in guides \/ ~FrontOnlyIfAsked)
       THEN /\ fronts' = IF fronts = 2 THEN 2 ELSE fronts + 1
            /\ stolen' = (stolen \/ "ax" \notin guides)
            /\ guides' = IF CloseOnGrant THEN guides \ {"ax"} ELSE guides
            /\ gone' = IF guides' = {} THEN 0 ELSE gone
            /\ failed' = IF ClearOnGrant /\ "ax" \in guides THEN FALSE ELSE failed
            /\ stale' = (stale \/ ("ax" \in guides /\ failed'))
       ELSE UNCHANGED <<fronts, stolen, guides, gone, failed, stale>>
    /\ UNCHANGED <<on, settings, beside, early, blind>>

\* One look for System Settings' window while a guide shows and Settings isn't open.
Watch ==
    /\ guides # {} /\ settings # "open"
    /\ LET n == gone + 1
           patience == IF ~beside /\ WaitForLaunch THEN Launch ELSE Grace
       IN IF CloseWhenSettingsGone /\ n >= patience
          THEN /\ guides' = {} /\ gone' = 0
               /\ early' = (early \/ (settings = "launching" /\ n < Launch))
          ELSE /\ gone' = IF n > Launch THEN Launch ELSE n
               /\ UNCHANGED <<guides, early>>
    /\ UNCHANGED <<on, seen, settings, beside, fronts, stolen, blind, failed, stale>>

Next ==
    \/ \E k \in Kinds, f \in BOOLEAN : Ask(k, f)
    \/ SettingsOpens \/ YouCloseSettings \/ YouSwitch \/ YouCloseGuide \/ FailureEnds \/ Look \/ Check \/ Watch

TypeOK ==
    /\ on \in BOOLEAN /\ seen \in BOOLEAN /\ settings \in {"closed", "launching", "open"} /\ beside \in BOOLEAN
    /\ guides \subseteq Kinds /\ gone \in 0..Launch /\ fronts \in 0..2
    /\ stolen \in BOOLEAN /\ early \in BOOLEAN /\ blind \in BOOLEAN /\ failed \in BOOLEAN /\ stale \in BOOLEAN

\* After a look that finds Accessibility on, no guide asks for it.
NoStaleGuide == "ax" \in guides => ~seen
\* Berang comes to the front only after a grant you started from Berang: while its guide was up.
FrontOnlyAfterAsking == ~stolen
\* Berang comes to the front at most once for a grant.
OncePerGrant == fronts <= 1
\* Never two guides at once.
OneGuide == Cardinality(guides) <= 1
\* A guide that found System Settings' window doesn't outlast it.
NotStranded == guides # {} /\ settings = "closed" /\ beside => gone < Grace
\* A guide doesn't close while System Settings is still opening.
NotCutShort == ~early
\* A guide shown while System Settings is open finds its window.
SeenOnShow == ~blind
\* A failure for missing Accessibility doesn't outlast the check that finds it on while its guide shows.
NoStaleFailure == ~stale
====

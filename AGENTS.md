# Working on Berang

Notes for coding agents. The README describes the app; this file describes how to change it.

## How features get built

- Model first. Before you build a feature that has state, timing, or several actors (the player, shortcuts, updates,
  windows, displays), write or extend a TLA+ model in `mac/Model`. Give each safeguard a constant that turns it off,
  and show that TLC finds a broken rule when it is off. Add the model to the TLC step in `.github/workflows/ci.yml`
  and describe it in the README's model sections. Code that implements a model names it in a doc comment.
- Prototype when the design is open. When a control can work in more than one reasonable way, build a clickable HTML
  page with two or three options and let the owner choose. Don't settle on one alone.
- Avoid accidental triggers. A plain click or a selection alone must never change what Berang does. Use a deliberate
  gesture, such as selecting text and then pressing the read shortcut.
- Teach every new control in the app: a tip in the player (`Tips.swift`) or a row on the home page.
- Write user-facing text plainly, without jargon.

## Design

- Every element on screen does a job for the user. Leave out taglines, decoration, cards inside cards, and anything
  the screen already says. If a screen needs a caption or a divider to make sense, change the layout instead.
- Explain only what's wrong or what the user must do: missing Accessibility access, no voice, a failed download. Put
  the rest in a tip or a home page row.
- Use the colors, fonts, and button styles in `Theme.swift`. Don't add one-off colors, sizes, or shadows.
- Numbers that change while you watch, such as the speed, use `.monospacedDigit()`.

## Motion

SwiftUI and AppKit animate well: `withAnimation`, springs such as `.snappy` and `.smooth`, `.transition`,
`.contentTransition(.numericText())`, and `NSAnimationContext` with `window.animator()` for windows.

- Animate a change only when it shows where something came from or went, such as a page swap or a panel opening.
- Don't animate what a shortcut does. Speed steps, jumps, and start and stop take effect at once.
- Use springs, so a new change starts from where the view is now. Things that appear use a spring or ease-out under
  0.3 s, never ease-in. Page swaps use `.snappy(duration: 0.2)`, as `RootView.go` does.
- With Reduce Motion on, replace movement with a short fade. Read `@Environment(\.accessibilityReduceMotion)` in
  SwiftUI and `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` in AppKit.
- The reading highlight follows the voice and never eases. `Highlight.draw` turns off implicit layer animation; keep
  it that way.

## Skills

`.agents/skills` (linked as `.claude/skills`) holds four of Emil Kowalski's skills, copied from
[emilkowalski/skills](https://github.com/emilkowalski/skills) at `64eb3de` under the MIT license, with each skill's
"Initial Response" step removed.

- `write-swift` for any Swift change. Its concurrency section assumes Swift 6.2's main-actor-by-default mode. This
  package uses tools version 6.0 without it, so keep the explicit `@MainActor` annotations.
- `emil-design-eng` and `apple-design` when you build or change UI.
- `review-animations` before you merge a change that adds or changes motion.

The design skills give CSS and JavaScript examples. Use the SwiftUI or AppKit equivalent, and follow the rules above
where they differ.

## Shipping

- Branch before you commit. Merge your own pull request with a rebase once every check passes.
- Release only when the owner says to. To release, tag `vX.Y.Z` on main and push the tag; `release.yml` builds, signs,
  and publishes the app with its update feed. Then check that the published `appcast.xml` lists the new version.

## Testing the app on the owner's Mac

- A test build (`mac/build-app.sh`) shares the installed Berang's settings, because the bundle ID is the same. Before
  testing, note the settings you will change (`speed`, `playerSpot`, `tips.learned`, `tips.shown`, and the
  `positions` entries for your test files). Restore them afterwards. Quit the test build when you finish.
- Send key presses only while a window you own is in front, and check that right before each key. Use a throwaway
  TextEdit document or a small test app. An app launched from the shell in the background can't bring itself to the
  front, so wrap the test app as a `.app` and start it with `open`.
- Click by screen position only after you confirm the target window's exact frame. The player's size changes with
  Start over, tips, and the speed panel, and its height changes where it is placed. A missed click lands in another
  app.
- UI scripting can't see the floating player. Find it with `CGWindowListCopyWindowInfo` and capture it with
  `screencapture -l <window id>`. Pick it by size: the reading highlight is a window on the same layer.
- Capture only Berang's own windows, never the whole screen.
- To select text in another app, set `kAXSelectedTextRangeAttribute` with a small Swift helper; AppleScript can't set
  a range. For buttons in Berang's window, use the accessibility press action, because Berang can't be brought to the
  front.
- Use test texts of 500 words or more. A short text finishes before the test does.

## Traps

- TLA+: in `x' = IF c THEN a ELSE b /\ y' = d`, the `ELSE` takes `b /\ y' = d`, and TLC reports `y` as unassigned.
  Put the `IF` in parentheses.
- TLA+: keep models small enough for CI. Let a config cover one actor of each kind when several behave alike, and run
  TLC with `-workers auto`.
- zsh doesn't split an unquoted `$VAR` into words, so `$J -cp …` runs nothing useful. Use a function or an array.
- Swift: setting a property inside its own `didSet` doesn't run the observer again. Clamp or round values where they
  are set.

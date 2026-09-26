# Trickpad pilot

This branch is an isolated pilot for replacing the user's BetterTouchTool mouse/trackpad gesture subset with the upstream Trickpad app **without modifying Trickpad itself**.

## Upstream

- Repository: `nweii/trickpad`
- Pilot baseline: upstream release **0.14.0**
- Pinned source commit: `e16f7fcd1613b9df944957cbda0e69d8eaf19163`
- License: GPL-3.0
- The end-user Mac must not need Homebrew, Xcode, or Command Line Tools. CI will build the app.

## Required behavior

### Magic Mouse — 3 gestures

| Gesture | Action |
|---|---|
| 3 Finger Swipe Up | ⇧⌘T |
| 3 Finger Swipe Down | ⌘W |
| 3 Finger Click | ⇧⌘V |

### Built-in MacBook trackpad — 6 gestures

| Gesture | Action |
|---|---|
| 3 Finger Click | ⇧⌘V |
| 3 Finger Swipe Up | ⇧⌘T |
| 3 Finger Swipe Down | ⌘W |
| 2 Finger Swipe Left | Page Forward |
| 2 Finger Swipe Right | Page Back |
| 3 Finger Double-Tap | Activate hovered Dock app, then ⌘H |

## Important Trickpad limitation

Trickpad 0.14.0 does **not** expose 2-finger swipes on the trackpad. Its trackpad swipe recognizers support 3–4 fingers. The two required 2-finger page-navigation gestures therefore stay native in macOS:

System Settings → Trackpad → More Gestures → Swipe between pages → **Scroll left or right with two fingers**.

This exactly covers the required left = forward / right = back behavior and avoids a redundant resident gesture recognizer.

The Dock double-tap action is not a built-in Trickpad action. The pilot config points it to one short-lived helper in `~/bin`; the helper will be built in CI and launched only when that gesture fires.

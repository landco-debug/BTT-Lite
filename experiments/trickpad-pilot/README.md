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


## Pilot build status

CI run **36278333271** completed successfully for TP02. Every stage passed: pinned-upstream fetch, upstream checks/build, Dock helper build, package assembly, signature smoke checks, binding smoke checks, and artifact upload.

Ready-to-test package: `Trickpad-Pilot-0.14.0.zip`.

GitHub Actions artifact digest (outer Actions artifact): `sha256:037830779de1d006e772548f83fd35f16fe5bde5fb9a7a79fa1022f4c471fd45`.

Extracted ready-to-install inner ZIP digest: `sha256:2e42a0b642297e15b4a00e213ba55e1e3828775cddc63027af8f8d05862b38d5`.

### First on-device test

1. Unzip `Trickpad-Pilot-0.14.0.zip`.
2. Open `pilot/install.command`.
3. Grant Accessibility to Trickpad and to `~/bin/trickpad-hide-hovered-dock-app`.
4. In System Settings → Trackpad → More Gestures, set **Swipe between pages** to **Scroll left or right with two fingers**.
5. From the Trickpad menu choose **Reload Settings**.
6. Test the three Magic Mouse bindings and the six trackpad behaviors before changing anything else.

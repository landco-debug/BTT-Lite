# Trickpad pilot — TP10 Window Hide

Upstream Trickpad 0.14.0 remains unmodified at e16f7fcd1613b9df944957cbda0e69d8eaf19163.
Target: Apple Silicon, macOS Sequoia 15+.

## Corrected double-tap requirement

Three-finger double-tap hides the application owning the visible window under the
pointer. The pointer may be over the window content or title bar. No Dock hover
or click is required. When windows overlap, the frontmost normal window at that
point wins. The action hides the entire application (like Command-H), not just
one window. Outside an application window it does nothing.

The helper obtains visible window bounds and owner PIDs via Quartz Window
Services, then calls NSRunningApplication.hide for that exact process. It does
not activate another application, inject Command-H, capture pixels or read
window titles. No resident helper, polling service or new package dependency.

The historical helper filename and signing identifier are intentionally retained
to preserve the installed binding and permission identity. The filename's
'dock' part no longer describes the action.

## Install

Extract Trickpad-Pilot-0.14.0-TP10-Window-Hide.zip, then open pilot/install.command.
Install over TP08; the installer restarts Trickpad and backs up the old config.
Existing Accessibility grants for Trickpad and the helper are still required.
No Homebrew or local developer tools are required.
Test by leaving the pointer over the Chrome window and double-tapping with three
fingers. Chrome should hide. The real gesture must be confirmed on the user's Mac.

## Unchanged gestures

Mouse: 3-finger up/down use the TP04 once-only wrappers; click sends Shift-Command-V.
Trackpad: same up/down/click bindings; native macOS two-finger page navigation.
TP04 swipe code, both wrappers and config.toml are checked byte-for-byte in CI.

## Validation

CI compiles/signs the arm64 helper, executes seven targeting tests (overlap,
background window, negative display coordinates, menu bar, desktop, empty list),
checks preserved TP04 code/bindings, and runs upstream checks/build.
No automated test substitutes for the user's physical gesture on Sequoia.

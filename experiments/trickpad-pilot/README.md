# Trickpad pilot — TP11 Window Hide

Upstream Trickpad 0.14.0 is pinned and unmodified. Apple Silicon / macOS Sequoia.

The trackpad three-finger double-tap hides the application owning the visible
window under the pointer, whether or not the pointer is over Dock. Overlapping
windows target the uppermost ordinary window. When there is no app window under
the pointer, the gesture has no effect. Hiding an app affects all of its windows.

TP11 follows a real-device TP10 report: the window hid after three attempts,
and Trickpad reported helper exit code 3. The helper first requests hide through
AppKit; if AppKit refuses, it uses its existing Accessibility grant to set the
same app's AXHidden attribute. Repeated dispatches of one gesture are coalesced
for a short quiet interval so the next window below is not also hidden. If both
hide requests fail, the helper saves one diagnostic at
~/Library/Logs/TrickpadPilot/window-hide.log and returns a real error.

The helper keeps its historical `trickpad-hide-hovered-dock-app` filename and
signature identity solely so existing bindings and grants remain valid.

## Install and check

Extract Trickpad-Pilot-0.14.0-TP11-Window-Hide.zip. Open
`pilot/install.command` to install over TP10; it backs up the prior config.
Leave the pointer over a Chrome window and double-tap the trackpad with three
fingers once. Chrome should hide without a Trickpad error popup. If it fails,
send the contents of ~/Library/Logs/TrickpadPilot/window-hide.log.

The Magic Mouse and trackpad three-finger swipe up/down bindings still use the
TP04 once-only wrappers. Both wrappers, the config and TP04 swipe code remain
byte-for-byte unchanged. Two-finger horizontal page gestures remain native macOS.

CI verifies the unchanged upstream build, arm64 helper signature, window-target
cases, duplicate-hide gate, and preservation of TP04 swipe code and bindings.
Only a real-device test can establish the physical gesture result on Sequoia.

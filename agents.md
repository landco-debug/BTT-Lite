# BTT Lite — hand-off log

This file is the authoritative hand-off for adjacent chats. Read it before changing the project. Keep changes incremental and preserve the low-resource design.

## Non-negotiable project requirements

- Target: MacBook Air M1, macOS Sequoia (macOS 15+), arm64.
- Goal: reproduce the user's actually used BetterTouchTool workflows with much lower idle RAM/CPU/GPU use.
- Native AppKit only for the main application/editor. Do not introduce Electron, WebView, Chromium, Core Data, a local server, or an always-running scripting runtime.
- All profiles/rules in every section must be editable through the GUI. Do not hard-code the user's shortcuts or gestures into the runtime.
- Rules support Global and application-specific scope, multiple ordered actions, enable/disable, duplication and deletion.
- User-specific BTT preset data must be imported locally, not committed to the public repository.
- Do not require Homebrew or local Developer Tools for the end user. CI should build the distributable `.app`.
- Work in small commits. Each functional commit gets a subsection in this file.

## Reference preset facts (local source, not committed)

The supplied BetterTouchTool preset contains 32 rules total: 19 keyboard/system-key-class rules, 7 Magic Mouse rules and 6 trackpad rules. It also contains application-specific rules. The importer has been tested against that file and imports all 32 rules.

Action families present in the reference preset include: send shortcut, run Apple Shortcut, launch app/path, terminal command, shell script, AppleScript, JavaScript selection transform, wait for clipboard change, Space switching, page back/forward, Launchpad, Bluetooth-device toggle, hovered-Dock-app activation and clipboard-history action. Unknown BTT actions must be preserved rather than silently discarded.

## C00 — Repository bootstrap and project charter

Status: complete.

Changes:
- Created the public `landco-debug/BTT-Lite` repository requested for this project.
- Added this hand-off file first so every later functional commit has an authoritative project log from the beginning.
- No runtime or UI code exists in C00.

## C01 — Bootstrap configurable AppKit editor and BTT importer

Status: implemented; macOS build verification is delegated to GitHub Actions.

Changes:
- Added Swift Package executable targeting macOS 15+.
- Added Codable configuration model: multiple profiles, app scopes, keyboard/system-key/gesture triggers and ordered multi-actions.
- Added atomic JSON `ConfigStore` in Application Support.
- Added BetterTouchTool `.bttpreset` importer. It maps all 32 rules from the supplied preset and preserves relevant BTT metadata without embedding the user's preset in source control.
- Added native AppKit menu-bar application and Settings window.
- Settings GUI supports profile add/duplicate/delete/import, category filtering, rule add/duplicate/delete, scope editing, trigger editing, multiple action add/delete/edit and enable flags.
- Added arm64 build/package script and GitHub Actions workflow.
- Pure Swift model/importer type-checks under Swift 6.2 on Linux; complete AppKit build awaits macOS CI.

Validation performed:
- `swiftc -parse Sources/BTTLite/*.swift` passes.
- `Models.swift` + `BTTImporter.swift` type-check under Swift 6.2.
- Import test against the supplied `Default.bttpreset` returns exactly 32 rules: Keyboard 19, Magic Mouse 7, Trackpad 6.

## C02 — Keyboard runtime and lightweight native action execution

Status: implemented; macOS compile/runtime verification is delegated to GitHub Actions.

Changes:
- Added global keyboard event tap using CoreGraphics/Accessibility. It matches the active profile, exact key code/modifier set and application scope.
- Synthetic key events are tagged and ignored by the event tap to avoid recursive trigger loops.
- Added sequential `ActionRunner` for common native actions: send shortcut, run Apple Shortcut, launch path, open URL, terminal command, shell script, AppleScript, clipboard wait, Space switching, page back/forward fallback, Launchpad and hovered-Dock activation.
- Bluetooth toggle is isolated into a short-lived helper executable linked against `IOBluetooth`; this prevents the always-on agent from loading the Bluetooth framework just to sit idle.
- Configuration changes restart only the lightweight keyboard event tap; no polling loop is used.
- Fixed BetterTouchTool import of `BTTEnabled` in addition to `BTTEnabled2`. The reference preset imports as 32 rules total, 29 enabled; 41 actions total, 36 enabled.
- JavaScript transform and clipboard-history actions remain preserved in the configuration but are explicitly not yet executed; JavaScript is intentionally deferred to an on-demand helper so JavaScriptCore/network support does not increase idle RSS.

Validation performed:
- All main-target Swift source still passes `swiftc -parse` under Swift 6.2.
- Pure model/importer type-check passes.
- Reference preset test: `rules=32 enabled=29`, `actions=41 enabledActions=36`.

Next planned commit:
- C03: low-overhead raw multitouch engine for both Magic Mouse and trackpad. Prefer an in-project runtime-loaded `MultitouchSupport.framework` bridge (no third-party runtime package) so all attached surfaces can be enumerated and classified independently.


## C02.1 — CI toolchain compatibility

Status: applied after the first GitHub Actions build exposed a toolchain mismatch.

Changes:
- Lowered only the Swift Package manifest tools declaration from 6.2 to 6.1.
- No runtime behavior or source-language target changed; the GitHub macOS 15 arm64 runner currently provides Xcode 16.4 / Swift 6.1.2.
- This keeps CI reproducible on the actual Sequoia runner instead of requiring an unnecessary newer toolchain.

Validation:
- C01 GitHub Actions failed before compilation solely because a 6.2 package manifest was rejected by SwiftPM 6.1.
- A new arm64 CI build is triggered by this commit.


## C02.2 — First macOS compiler fixes

Status: applied from GitHub Actions diagnostics.

Changes:
- Enter the AppKit application from a `MainActor.assumeIsolated` top-level block so the main-actor `AppDelegate` is initialized legally under Swift 6 concurrency checking.
- Removed the actor-isolated `stop()` call from `KeyboardEngine.deinit`; the engine is application-lifetime and is explicitly restarted/stopped by its owner.
- Replaced the nonexistent CoreGraphics enum case `CGEventType.systemDefined` with the documented raw event type 14 used by AppKit system-defined media/function-key events.
- Fixed mixed `NSView` action-editor arrays that attempted to use `isEnabled` on `NSScrollView`; controls and text-editability are now toggled separately.

Validation:
- These changes address every source compile error reported by the C02.1 macOS 15 arm64 workflow.
- A new CI run is triggered by this commit.


## C03 — Native Magic Mouse and trackpad gesture engine

Status: implemented; GitHub Actions will verify the macOS 15 arm64 compile.

Changes:
- Added a tiny in-project bridge that runtime-loads Apple's private `MultitouchSupport.framework` with `dlopen/dlsym`; there is no third-party runtime package and no polling loop.
- Enumerates all current multitouch devices with `MTDeviceCreateList` and classifies built-in/external trackpads versus Magic Mouse using built-in status plus IORegistry product/surface metadata.
- Private contact-layout assumptions are isolated in one file and guarded by contact-count/state/range checks so later macOS compatibility fixes remain localized.
- Added a lock-protected, pure-Swift recognizer core for configurable N-finger left/right/up/down swipes and N-finger double-taps.
- Added physical N-finger click recognition by correlating a narrow CoreGraphics mouse-click tap with the most recent live raw-touch frame; matched configured clicks suppress the original down/up pair so the normal click is not accidentally executed as well.
- Gesture matching respects enabled state, active profile and application bundle scope, then reuses the existing sequential `ActionRunner`.
- The raw-touch bridge is started only while the active profile actually contains enabled gesture rules; the click event tap is installed only if an enabled physical-click rule exists.
- Input Monitoring is requested only when gestures are enabled; Accessibility is requested for physical-click interception when needed.
- Added explicit IOKit linkage to the main target for lightweight device classification.
- No GUI expansion was needed: the C01 editor already exposes device, finger count, gesture kind and swipe direction for every gesture rule.

Validation performed before commit:
- Main target and Bluetooth-helper sources parse successfully under Swift 6.2 on Linux.
- Pure recognizer test passes for a two-finger left swipe and a three-finger double-tap.
- C02.2 macOS 15 arm64 GitHub Actions build is green before layering C03.

Compatibility note:
- `MultitouchSupport.framework` is a private Apple framework. It is runtime-loaded and isolated deliberately; App Sandbox must remain disabled. If Apple changes the private ABI in a future macOS release, `MultitouchBridge.swift` is the single repair point.

Next planned commit:
- C04: close remaining imported-action gaps (on-demand JavaScript selection transform and clipboard-history behavior), then package a testable artifact and measure real idle RSS/CPU on the user's M1.


## C04 — On-demand JavaScript selection transform

Status: implemented; macOS arm64 CI will compile both the main agent and the new helper.

Changes:
- Implemented the active imported BetterTouchTool action “Transform & Replace Selection With Java Script”.
- The main agent copies the current selection, sends the text plus the user-configured script to a short-lived bundled helper, writes the returned text to the pasteboard and pastes it back over the selection.
- JavaScriptCore is linked only by `BTTLiteJavaScriptHelper`, never by the always-running BTT Lite process, so the feature adds no persistent JavaScript engine to idle RSS.
- The helper exposes a minimal Promise-based `fetch()` compatibility layer backed by Foundation `URLSession`; this supports the exact async Google-Translate script present in the reference preset, including `response.ok`, `status`, `json()`, `text()` and `encodeURIComponent`.
- Helper requests/results use JSON over stdin/stdout, avoiding shell quoting and command-line length issues.
- Network and JavaScript timeouts are bounded; failures leave the current selection unchanged and only log an error.
- The two clipboard-history actions in the supplied preset are both disabled, so their full BTT history UI remains preserved/configurable but intentionally unimplemented at this milestone; no always-on clipboard polling was added.

Resource rationale:
- JavaScriptCore and network machinery exist only in a process created when this action is invoked.
- No new background timer, database or resident service was introduced.

Validation performed before commit:
- Main, Bluetooth-helper and JavaScript-helper Swift sources parse successfully.
- C03 builds successfully on GitHub's macOS 15 arm64 runner before C04 is layered.

Next planned commit:
- C05: produce the first installable test artifact from CI, add lightweight runtime diagnostics for RSS/CPU/device status, and use the user's real preset for on-device functional testing without committing personal preset data.


## C05 — CI smoke validation for the first test artifact

Status: implemented.

Changes:
- Added post-build checks on the same macOS 15 arm64 runner that produces the distributable.
- CI verifies the main executable and both on-demand helpers are present and executable inside the app bundle.
- CI runs strict deep code-signature verification and asserts that the main executable is arm64.
- CI executes the JavaScript helper with an async no-network transform and requires the exact `HELLO` JSON result, proving JavaScriptCore/Promise/helper IPC works before an artifact is uploaded.
- CI also requires the final inner `BTT-Lite-arm64.zip` to exist and be non-empty.

Release/testing policy:
- Do not hand a build to the user as the current test build unless this smoke stage and the full workflow are green.
- The GitHub Actions artifact is an outer archive containing the ready-to-install inner `BTT-Lite-arm64.zip`.

Next step after green CI:
- Hand the inner ZIP to the user for real-device testing on the MacBook Air M1: import the supplied BTT preset, grant Accessibility/Input Monitoring, test keyboard + Magic Mouse + trackpad rules, then measure idle RSS/CPU before adding more optional features.


## C05.1 — Correct JavaScript-helper smoke assertion

Status: applied from the first C05 smoke run.

Changes:
- The helper itself passed and returned `{"ok":true,"result":"HELLO"}`.
- JSONEncoder correctly omits optional fields whose value is `nil`, so the original smoke assertion was too strict by requiring an explicit `"error": null`.
- CI now validates the semantic contract instead: `ok == true`, `result == "HELLO"`, and no non-empty error.

Validation:
- The failed C05 run confirmed the app compiled, signed, and the JavaScript helper actually executed the async transform successfully; only the test expectation was wrong.
- A replacement CI run is triggered by this commit.


## C06 — First on-device bug-fix pass

Status: implemented from the first MacBook Air M1 / macOS Sequoia test report; CI validation pending at commit time.

User-reported findings addressed:
- Trackpad 3-finger click opened PasteNow but also typed a stray Russian “ф”.
- Trackpad 3-finger double-tap did not execute the imported hide workflow.
- ⌘L Translate&Replace did not work because Chrome also received ⌘L.
- Fn+4 Bluetooth toggle did not work reliably.
- Magic Mouse 3-finger left/right swipe did not switch Spaces.
- Intermittent system alert sounds were heard while using configured triggers.
- Settings window could remain behind Chrome.
- User was unsure whether Accessibility/Input Monitoring permissions were both granted.

Changes:
- Keyboard triggers now use an intercepting event tap and consume a matched original key event instead of listen-only observation. This prevents the frontmost app from also executing the same hotkey; notably ⌘L no longer moves focus to Chrome's location field before the JavaScript selection transform copies the selection.
- Synthetic keyboard actions now use a HID-system event source plus explicit modifier down/up events. This better follows the hardware path used by Mission Control/global hotkey listeners and is intended to fix Space switching, ⌘H and similar system/application shortcuts.
- Removed the dangerous virtual-key-0 fallback. A malformed send-shortcut action is skipped and logged instead of typing “A” / Russian “Ф”.
- Bluetooth helper now resolves paired devices by normalized MAC address and by device name, accepts colon/hyphen address forms, and verifies/retries disconnect/connect state changes.
- Swipe recognizer now fires as soon as direction/distance are unambiguous rather than waiting for every contact to disappear. Thresholds were modestly relaxed for Magic Mouse, and double-tap timing/movement tolerances were made less brittle.
- Settings window is floating and explicitly ordered front so it can be brought above Chrome from the menu-bar app.
- Added a Permissions Status menu item showing Accessibility and Input Monitoring state and allowing a re-request/open of the relevant Privacy pane.

Preset discrepancy found during diagnosis:
- The supplied `Default.bttpreset` does NOT contain a Trackpad “3 Finger Swipe Down → ⌘W” rule. It contains the corresponding Magic Mouse rule, plus Trackpad 3 Finger Click, 3 Finger Double-Tap, 3 Finger Swipe Up, 2 Finger Swipe Left/Right and the now-unwanted 4 Finger Click. Therefore this one missing Trackpad rule cannot be recovered by an exact importer from that file; do not hard-code it into the importer. It should be added/duplicated in the editable GUI or imported from a newer preset that actually contains it.
- The supplied Fn+4 rule contains a disabled “Run Shortcut: Imgur” action and an enabled “Toggle Bluetooth Device Connection” action for device name `Win`; the importer correctly preserves both enabled states.

Next validation:
- GitHub macOS 15 arm64 compile/sign/smoke workflow.
- Then retest on the user's M1: Trackpad 3 Finger Click, 3 Finger Double-Tap, ⌘L Translate&Replace, Fn+4 Bluetooth, Magic Mouse 3 Finger Space swipes, system alert sounds and Settings window ordering.


## C07 — Shortcut editor UX and RuSwitcher 3.3.0 compatibility

Status: implemented; macOS CI validation pending at commit time.

User report addressed:
- The bottom-left + appeared to do nothing while the Trackpad category filter was active.
- A duplicated Trackpad swipe could be changed to Down, but assigning ⌘W required raw key-code/modifier numbers and was not understandable.
- With RuSwitcher 3.3.0 running, BTT Lite synthetic key events polluted RuSwitcher's conversion buffer, producing repeated "aaaa/фффф" and system sounds.

Root causes:
- `addRule()` always created a Keyboard rule. Under the Trackpad/Magic Mouse/Application filtered views the new rule was immediately hidden, so the button looked broken.
- The editor exposed only raw keyCode/modifier fields for Send Keyboard Shortcut actions.
- RuSwitcher 3.3.0's `KeyboardMonitor.swift` ignores synthetic events carrying marker `0x52555300`. BTT Lite used a different marker, so RuSwitcher processed BTT Lite's injected shortcuts as typing.
- BTT Lite consumed configured hotkey key-down events but previously let their key-up events through.

Changes:
- + now creates a trigger matching the current category so the new row remains visible.
- Added one-shot native shortcut recorders for Keyboard triggers and Send Keyboard Shortcut actions. Press Record, then press the desired shortcut; Esc cancels. Raw fields remain available for advanced editing.
- Settings is exempt from runtime hotkey interception while frontmost, allowing existing shortcuts to be re-recorded.
- Matched hotkeys consume both key-down and corresponding key-up.
- Synthetic actions now use RuSwitcher 3.3.0's compatibility marker `0x52555300`, keeping BTT Lite injected shortcuts out of RuSwitcher's conversion buffer.
- Synthetic modifier transitions are emitted as `flagsChanged`, matching native macOS modifier semantics.

Retest:
- In Trackpad view, + must immediately create/select a Trackpad rule.
- For duplicated 3 Finger Swipe Up changed to Down, choose Send Keyboard Shortcut → Record Shortcut → press ⌘W.
- With RuSwitcher 3.3.0 enabled, normal autocorrection and BTT Lite gestures should coexist without repeated a/ф runs or extra alert sounds.


## C08 — Deterministic gesture arbitration and axis locking

Status: implemented after confirmed on-device instability; macOS CI regression validation pending at commit time.

User-reported failure:
- 3-finger up/down and left/right were intermittently confused.
- A 3-finger Space swipe could also open/close a browser page.
- Some vertical swipes appeared to do nothing.
- Occasionally both the native Space switch and a BTT Lite browser action happened in the same physical gesture.

Root cause found in BTT Lite:
- The C03/C06 recognizer started measuring from the very first touching finger and used the moving centroid. When fingers landed sequentially (1→2→3), adding the second/third finger could move the centroid by a large amount before the real swipe began. Because the user's profile also has 2-finger page-navigation swipes, a gesture intended as 3 fingers could transiently be recognized as a 2-finger left/right swipe.
- C06 intentionally began firing as soon as a single frame crossed a weak 1.15 axis-dominance threshold. A slightly diagonal start could therefore commit to the wrong axis before the intended direction became clear.
- The recognizer used max finger count and had no explicit arbitration for finger-count changes or axis locking.

Relevant BetterTouchTool / Apple behavior used as design guidance:
- BetterTouchTool's author states its three-finger swipe recognition requires exactly three touching fingers; BTT also uses minimum-touch-duration / post-click conflict guards for ambiguous touch states.
- BTT continuous swipe recognition exposes “Movement Required To Begin” and an Automatic axis mode that locks to the first dominant axis rather than repeatedly reclassifying direction.
- Apple's public gesture model is phase-based (begin/changed/end/cancel) and exposes a gesture axis; the implementation below mirrors those state-machine semantics even though BTT Lite reads global raw contacts through MultitouchSupport.

Changes:
- Added a 75 ms finger-membership settle window. Swipe tracking begins only after the same contact IDs/finger count have remained stable, so finger placement itself cannot become a swipe.
- When the finger count increases, tracking rebases after it settles; when fingers begin lifting, lower-finger swipe recognition is suppressed until all contacts leave the surface. This closes 3→2, 4→3, etc. tail-trigger bugs.
- Direction now requires a dominant-axis candidate for three consecutive frames, then locks for the remainder of that touch session.
- Final triggering requires stronger 1.60 axis dominance. Ambiguous diagonal motion produces no destructive action rather than guessing.
- Once an axis is locked it cannot flip from horizontal to vertical (or vice versa) within the same gesture.
- Trackpad and Magic Mouse have separate movement distances; Magic Mouse keeps the lower threshold needed for its smaller surface.
- Maximum deliberate swipe time increased to 1.75 s so slower gestures do not appear to “hang”.
- Click correlation now also requires the observed finger count to have been stable for 55 ms before a multi-finger click can fire.
- The same arbitration logic applies to every swipe/finger count on both Trackpad and Magic Mouse, not only the reported 3-finger cases.

Regression coverage:
- Added CI tests for sequential 1→2→3 landing, all four cardinal directions, diagonal rejection, axis lock/no mid-gesture flip, 3→2 tail suppression, slow swipes and 3-finger double-tap with sequential finger landing.
- CI now runs those pure-Swift recognizer tests before building the application.

Retest focus:
- Keep macOS native 3-finger left/right Space switching enabled and BTT Lite vertical 3-finger actions enabled.
- Repeatedly perform left/right, up/down and deliberately diagonal 3-finger movements. Wrong-axis actions and 2-finger page-navigation leakage should be gone; intentionally diagonal gestures may be ignored by design.


## C09 — Restore closed web-app context and repair Fn/Bluetooth path

Status: implemented from the next on-device report; macOS CI validation pending at commit time.

User report:
- The imported 3-finger Swipe Up behaves differently from BTT for browser/web-app workflows: BTT restores the recently closed item/app, BTT Lite does not.
- Fn+4 still does not toggle the configured Bluetooth device.

Exact preset facts verified locally (personal device identifiers are intentionally not committed):
- Trackpad 3 Finger Swipe Up is a Send Keyboard Shortcut action for ⇧⌘T.
- The matching close workflow uses ⌘W.
- Fn+4 is keyCode 21 with the Function/Fn modifier bit (8388608); the Bluetooth toggle action is enabled and an unrelated Shortcut action in that same rule is disabled.

Root causes found in BTT Lite:
- Send Keyboard Shortcut was always posted to the current global foreground context. After ⌘W closes the last window of a standalone browser/web app, macOS can move focus to another app; the later ⇧⌘T therefore goes to the wrong process. BTT's behavior preserves the useful close/restore context.
- The Fn trigger path listened only to keyDown/keyUp. Apple exposes Fn as `maskSecondaryFn` and also reports modifier changes through flagsChanged/source-state APIs; relying on only the keyDown event's flags is brittle on laptop keyboards.
- The packaged app did not declare `NSBluetoothAlwaysUsageDescription`. Bluetooth is a protected macOS resource, so a child helper can be denied/terminated by TCC when the responsible app lacks that purpose string. This is a concrete packaging bug, not a device-address/import problem.

Changes:
- ⌘W now remembers the frontmost application context for ten minutes.
- A later ⇧⌘T first restores that remembered target: if it is still running, BTT Lite activates it and posts the shortcut directly to its PID; if a standalone web app terminated after its last window closed, BTT Lite reopens the remembered app bundle instead of sending ⇧⌘T to an unrelated foreground app.
- The close/restore context logic lives in ActionRunner, so it applies to the same shortcut pair regardless of whether the trigger came from Trackpad, Magic Mouse, keyboard, or an application-specific rule.
- KeyboardEngine now observes flagsChanged and combines event flags with current combined-session/HID source flags. This makes Fn/Globe modifier matching robust for imported Fn+number shortcuts while preserving exact modifier matching for ordinary hotkeys.
- Added the required `NSBluetoothAlwaysUsageDescription` purpose string to the packaged app. The Bluetooth helper remains short-lived, so IOBluetooth still adds no idle RSS to the main agent.
- Bluetooth helper now only acts on paired devices, retries disconnect long enough for profile teardown, and retries connection attempts for sleeping devices.
- CI now asserts that the packaged Info.plist actually contains the Bluetooth purpose string.

Expected first-run behavior after replacing C08:
- The first real Bluetooth action may cause macOS to show a Bluetooth privacy prompt for BTT Lite. It must be allowed once. Existing Accessibility/Input Monitoring grants are separate.

Retest:
- Close a standalone browser/web app with the configured ⌘W swipe, then restore it with the ⇧⌘T swipe.
- Test the same close/restore pair in an ordinary browser tab/window.
- Press Fn+4 with Bluetooth already enabled; allow the Bluetooth permission prompt if macOS shows it, then verify disconnect and reconnect on consecutive presses.


## C10 — Physical Fn chord interception and bundled Bluetooth helper

Status: implemented after C09 on-device retest proved the Fn+4 trigger still never fired; macOS CI validation pending at commit time.

New on-device evidence:
- Pressing Fn+4 selected a Finder item / typed the character “4” into text fields.
- No Bluetooth privacy prompt appeared.
- This proves the failure occurs before the Bluetooth action: BTT Lite was not recognizing and consuming the Fn+4 chord, so the Bluetooth helper was never launched.
- Screenshots from BetterTouchTool 6.017 confirm the intended action is “Toggle Bluetooth Device Connection”; its configuration UI resolves the currently paired device as “Lenovo”, while the action tile/preset retains the older display name “Win”. The saved hardware address is therefore the authoritative identity; BTT Lite already prefers the address over the stale name.

Exact preset trigger:
- Fn+4 is a keyboard trigger with keyCode 21 and modifier value 8388608 (Fn / kCGEventFlagMaskSecondaryFn).
- The unrelated Imgur Shortcut action on that rule is disabled; the Bluetooth toggle action is enabled.

Root cause:
- C09 tried to infer Fn by OR-ing the flags of the keyDown event and event-source modifier tables. On Apple laptop keyboards the physical Fn/Globe key is special: the reliable physical transition is a flagsChanged event for kVK_Function (virtual key code 63), and the number-key keyDown can still arrive without the Fn bit. The observed literal “4” is exactly the failure mode of that approach.
- The keyboard tap was installed at the session level. Fn/Globe is a hardware modifier, so C10 first installs a HID-level event tap and falls back to the session level only if necessary.
- C09 added the Bluetooth privacy key only to the outer app while executing the Bluetooth code from a bare child Mach-O. C10 packages the Bluetooth helper as its own nested app bundle with its own Bluetooth purpose string, giving macOS TCC an unambiguous responsible bundle when IOBluetooth is first used.

Changes:
- KeyboardEngine now tracks physical Fn/Globe state explicitly from flagsChanged keyCode 63, with HID hardware key-state fallback via CGEventSource.keyState(.hidSystemState, key: 63).
- Fn state is merged into a normal number-key event before exact trigger matching. A matched Fn+4 now consumes both the “4” key-down and key-up, so Finder/text fields cannot receive the literal digit.
- Keyboard event tap now prefers cghidEventTap and automatically re-enables itself if macOS disables it after timeout/user-input recursion.
- Caps Lock state no longer prevents an otherwise exact imported shortcut unless Caps Lock is explicitly part of that shortcut.
- Bluetooth helper is now packaged as Contents/Helpers/BTTLiteBluetoothHelper.app with its own Info.plist and NSBluetoothAlwaysUsageDescription, while remaining a short-lived process so the main agent's idle RSS is unchanged.
- Bluetooth action failures are no longer silent: if the helper launches but cannot find/toggle the paired device or is denied, BTT Lite shows the helper error in an alert. This separates “hotkey not detected” from “Bluetooth operation failed” during real-device testing.
- CI verifies the nested helper executable, signature, and Bluetooth purpose string.

Retest contract:
1. With Finder frontmost, Fn+4 must NOT select a file or type “4”.
2. With a text field focused, Fn+4 must NOT insert “4”.
3. On the first actual Bluetooth attempt, macOS may ask for Bluetooth permission; allow it.
4. If Bluetooth still cannot toggle, BTT Lite must now show a concrete “Bluetooth action failed” diagnostic instead of silently doing nothing.


## C11 — Eliminate sticky Fn state, non-invasive shortcut injection, safer Bluetooth toggle

Status: implemented after C10 on-device retest; macOS CI validation pending at commit time.

On-device evidence:
- C10 finally recognized Fn+4 and executed the Bluetooth action once.
- After Input Monitoring was granted, plain number keys became unsafe: plain 4 could no longer be typed, and plain 1 could execute the configured Fn+1 action.
- The Bluetooth reconnect attempt returned -536870186 / 0xE00002D6, which is kIOReturnTimeout.
- The Linux Bluetooth receiver later needed its Bluetooth stack reset and showed an mpris-proxy crash. Causation is not proven, but C10's repeated state-changing openConnection/closeConnection retries were unnecessarily aggressive and are removed.
- Magic Mouse 3-finger left/right did not switch Spaces; attempting it could activate the user's transcription app instead.

Root causes:
- C10 cached `fnIsDown`. On an Fn release, the flagsChanged event could arrive while `CGEventSource.keyState(.hidSystemState, key: 63)` still briefly reported down. The cached state then remained true indefinitely. Every later number key could therefore be matched as Fn+number. This exactly explains the plain 1/plain 4 failures.
- C06/C10 synthetic shortcuts emitted separate fake modifier `flagsChanged` events (Control/Option/Shift/Command down/up). Modifier-key hotkey utilities can interpret those as genuine user modifier presses. A Magic Mouse Space action therefore had an avoidable path to trigger a transcription utility before/while Ctrl+Arrow was posted.
- The C10 Bluetooth helper actively retried connect up to three times and disconnect up to ten times. After an I/O timeout this can stack additional state changes onto a controller/remote device that is already unresponsive.

Changes:
- Fn is no longer cached. For each main keyDown, BTT Lite samples the physical kVK_Function key state (keyCode 63) at that exact moment and also accepts maskSecondaryFn on that event. No later plain number press can inherit an old Fn state.
- Keyboard tap no longer subscribes to the global flagsChanged stream. This reduces event traffic and removes the race that created sticky Fn.
- Matched Fn+number chords still consume both keyDown and keyUp, so the digit is not delivered to Finder/text fields when Fn is genuinely held.
- All synthetic shortcuts now post only the actual keyDown/keyUp with the desired modifier flags. Separate fake modifier transitions were removed. This applies to Mission Control Space switching, browser navigation, Cmd+W / Shift+Cmd+T, selection copy/paste, and every other Send Keyboard Shortcut path.
- The event source remains hidSystemState and the RuSwitcher compatibility marker is preserved. localEventsSuppressionInterval is zeroed to avoid a mouse gesture suppressing the immediately generated system shortcut.
- Magic Mouse 3-finger left/right therefore executes Ctrl+Arrow without manufacturing standalone Control-key presses that another hotkey app can consume. System Settings' “Swipe between full-screen applications” can remain OFF, matching the user's original BTT setup.
- Bluetooth connect/disconnect now sends exactly one state-changing IOBluetooth request, then passively observes state for a bounded grace period. There are no automatic retries after timeout/busy/offline conditions.
- Bluetooth errors are decoded to useful names (including I/O timeout) and explicitly say that no automatic retry was made.
- Bluetooth helper now links IOKit directly for canonical IOReturn constants.
- CI smoke launches the nested Bluetooth helper with no arguments and requires its expected usage exit, in addition to bundle/signature/privacy checks.

Safety note:
- The Linux mpris-proxy crash cannot be attributed conclusively to BTT Lite from the screenshot alone. However, removing repeated connect/disconnect requests is the safer controller/remote-device behavior after a timeout and eliminates one plausible stressor.

Retest contract:
1. Leave Input Monitoring enabled. Type 111144441234567890 repeatedly: plain digits must remain plain digits and must not invoke Fn actions.
2. Hold Fn and press 1, then Fn+4: only the explicit Fn chords should fire; their digits must not leak to the frontmost app.
3. For Bluetooth, test at most one disconnect and one reconnect. If reconnect times out again, stop there and report the C11 diagnostic; do not power-cycle repeatedly for the test.
4. With Magic Mouse, 3-finger left/right should switch Spaces without activating Handy. The macOS Mouse setting for “Swipe between full-screen applications” may remain disabled.


## C12 — BTT-compatible Fn state machine, Mission Control shortcut resolution, Bluetooth result semantics

Status: implemented after C11 on-device retest and targeted documentation/forum research; macOS CI validation pending at commit time.

Observed C11 failures:
- Fn+4 could launch the Bluetooth action once but also leaked the character “4” into the focused field; later presses often did nothing.
- Plain digits were now safe, but Fn+number actions that had worked in earlier builds became rare/delayed.
- Bluetooth showed the internally contradictory alert “disconnect failed: success (0)”.
- Magic Mouse 3-finger left/right still did not switch Spaces, although the C11 removal of fake Control transitions stopped accidental Handy activation.

Research conclusions:
- BetterTouchTool's author explicitly documents that macOS does not offer ordinary Fn shortcuts; BTT uses its own shortcut system for Fn. Fn shortcuts are unavailable in Secure Input mode. Apple exposes Fn as CGEventFlags.maskSecondaryFn on keyboard/mouse/flagsChanged events.
- The C11 HID-state-only Fn sampling was therefore the wrong model. It removed C10's sticky flag but also discarded the reliable Fn transition stream used by a custom shortcut implementation.
- BetterTouchTool's author also explicitly states that the normal “Move Left/Right a Space” actions use the shortcuts configured in System Settings → Keyboard → Keyboard Shortcuts → Mission Control. They are not hard-coded Ctrl+Arrow actions inside BTT.
- macOS stores those actions as AppleSymbolicHotKeys IDs 79 (left) and 81 (right). Contemporary Mac defaults commonly encode Control+Arrow with modifier value 8650752, i.e. Control plus the secondary-Fn bit. C11 hard-coded only Control, so it did not actually reproduce the system shortcut BTT invokes.
- BTT's action definition confirms predefined action 276 means “Toggle Bluetooth Device” connection, not Bluetooth radio power.
- Apple's IOBluetooth documentation states closeConnection() is synchronous and returns kIOReturnSuccess only when the baseband connection has successfully been closed. Therefore C11's later isConnected() poll was invalid as a reason to convert status 0 into failure. It directly created the impossible “failed: success (0)” alert.
- BTT itself is closed source, so its private Bluetooth implementation cannot be asserted. However the documented action semantics and public IOBluetooth API are sufficient here; established macOS Bluetooth utilities use openConnection/closeConnection for this operation.

Fn/hotkey fixes:
- Added a dedicated KeyboardModifierState driven by flagsChanged. Fn-down is learned from maskSecondaryFn; the Fn release edge overwrites state rather than OR-ing stale HID/session values. This preserves C10's protection against sticky Fn while restoring the transition-based model needed for reliable Fn+number shortcuts.
- KeyboardEngine again subscribes to flagsChanged and prefers the session event tap (HID remains fallback).
- On an event-tap disable/re-enable, cached modifier and claimed-key state are reset defensively.
- The first matched keyDown claims that physical key until keyUp. Every autorepeat keyDown for an already-claimed key is swallowed. This fixes the exact C11 “action fires, then a literal 4 appears” sequence when Fn is released while the number key is still held.
- Fn release cannot poison later ordinary digits; ordinary 1–0 remain ordinary.

Space-switch fixes:
- Added SystemSymbolicHotKeyResolver. “Move Left a Space” now resolves AppleSymbolicHotKeys ID 79 and “Move Right a Space” ID 81 from the user's current macOS preferences and sends the exact configured key code/modifier mask.
- If those preferences cannot be read, the MacBook fallback is Control+Fn+Left/Right, not C11's Control-only approximation.
- Numeric-pad/help modifier bits are now preserved when synthesizing a configured system shortcut.
- This applies to any trigger that invokes moveSpaceLeft/moveSpaceRight, including the user's Magic Mouse 3-finger swipes. The macOS Mouse setting “Swipe between full-screen applications” can remain off because BTT Lite triggers the Mission Control keyboard action, matching BTT's documented behavior.

Bluetooth fix:
- Removed the post-success isConnected polling test. One closeConnection/openConnection call is issued and its synchronous IOReturn is authoritative.
- A successful closeConnection now exits successfully immediately; it can no longer produce “disconnect failed: success (0)”.
- Non-success statuses (including timeout) are still reported and never automatically retried, preserving the C11 safety change for the Mac/remote Linux Bluetooth stacks.

Regression coverage added:
- Fn press → Fn+number → Fn release → plain number, verifying Fn cannot remain sticky.
- Fn supplied directly on a key event without a prior transition.
- Parsing of modern Mission Control IDs 79/81 with modifier 8650752, verifying both Control and secondary-Fn are retained.
- CI runs these tests before the application build.

Retest contract:
1. Hold Fn and press 1/2/3/4/5/6 as configured: each action should fire once with no leaked digit and no long delay.
2. Release Fn, then type 1234567890 normally: no action should fire.
3. Fn+4 disconnect: status 0 must be treated as success with no error dialog. Press Fn+4 again once to reconnect; if openConnection returns timeout, report that exact error and stop—no retries are generated.
4. Magic Mouse 3-finger left/right: the current System Settings Mission Control shortcut is now used exactly. If the system's “Move left/right a space” shortcuts themselves are disabled/conflicted, BTT's documented behavior also depends on fixing them.


## C13 — Magic Mouse fast-path reliability and conservative Bluetooth reconnect hardening

Status: implemented after C12 on-device retest; macOS CI validation pending at commit time.

Observed C12 behavior:
- Fn+4 reliably disconnects the configured Bluetooth receiver, but reconnect succeeds only about every other attempt.
- Magic Mouse 3-finger Space swipes are recognized only around one time in ten, often appear to work in only one direction, and sometimes the Space transition happens noticeably after the physical swipe.
- Ordinary digit entry is no longer reported broken, so C13 keeps the C12 Fn state machine unchanged.

Root causes / design corrections:
- C08's 75 ms settle window, three confirmation frames and 6% travel were deliberately conservative after Trackpad wrong-axis bugs. Those same thresholds are too slow/strict for the much smaller Magic Mouse surface.
- MultitouchSupport state 5 is BreakTouch: the final position-bearing touch sample. BTT Lite previously discarded it, so a fast mouse swipe could lose the final sample that crossed the distance threshold.
- Same-count contact identity replacement cancelled the entire gesture. On Magic Mouse a brief contact loss/reacquire should instead safely rebase the measurement.
- BetterTouchTool uses the current macOS Mission Control shortcuts for Move Left/Right a Space. The resolver therefore needs the effective com.apple.symbolichotkeys preference, not BTT Lite's app-local UserDefaults cache.
- Bluetooth reconnect can race remote profile teardown. Apple's IOBluetooth API provides a synchronous openConnection overload with an explicit page timeout, so reliability can be improved with one longer request rather than repeated commands.

Magic Mouse changes:
- Multitouch bridge now accepts MakeTouch, Touching and BreakTouch samples (states 3...5).
- Contact identity now uses the actual fingerID field (offset 24) rather than pathIndex.
- The framework touch timestamp is propagated into recognition instead of replacing it with callback scheduling time.
- Trackpad thresholds remain unchanged.
- Magic Mouse gets a dedicated fast path: 35 ms settle, 4% trigger travel, 1.8% lock travel, two confirming frames, 1.25 lock dominance and 1.30 final dominance.
- Same-count identity replacement on Magic Mouse rebases after the short settle window instead of cancelling the session. Trackpad retains C08's stricter behavior.
- Regression tests cover fast three-finger horizontal swipes in both directions and identity replacement during a swipe.

Mission Control dispatch:
- SystemSymbolicHotKeyResolver now synchronizes and reads the effective com.apple.symbolichotkeys CFPreferences domain directly.
- The exact configured key/modifier tuple is still preferred; modern Control+Fn+Arrow remains fallback only if no tuple can be read.
- The synthetic Mission Control key-down is held for 12 ms before key-up instead of being a zero-duration chord.
- The standard animated BTT action semantics are preserved; no private/no-animation Space switch was substituted.

Bluetooth reconnect changes:
- Bluetooth toggles are serialized. A second Fn+4 cannot start another helper while one synchronous IOBluetooth operation is still in flight.
- After a successful disconnect, an immediate reconnect waits only until a 1.25 s teardown quiet period has elapsed.
- Connect issues exactly one openConnection request with page timeout 0x4000 (about 10.24 s).
- If the request returns non-success but the device is already connected, or becomes connected during a short 750 ms passive observation window, the action succeeds.
- No automatic connect retry and no disconnect retry are issued.

Retest contract:
1. Magic Mouse: 20 three-finger swipes left and 20 right. Both directions should trigger at comparable rates and response should start during the swipe rather than after a long pause.
2. Trackpad: quick sanity test of existing three-finger directions; its C08 thresholds were not changed.
3. Bluetooth: disconnect once with Fn+4, then reconnect once. If reconnect still fails, report the exact C13 error/status rather than repeatedly retrying.
4. Fn+1..Fn+6 and ordinary digits should behave exactly as in C12; C13 does not alter Fn recognition.


## C14 — Left/right modifier fidelity and modifier-guarded gestures

Status: implemented after the user intentionally skipped installing C13; macOS CI validation pending at commit time.

User decisions / requirements:
- For Magic Mouse, the user is moving back toward Apple's native gesture layout: two-finger horizontal swipes for Spaces and one-finger horizontal swipes for page back/forward.
- The user may repurpose two-finger vertical Magic Mouse swipes for close/restore actions, but only while a chosen keyboard modifier is held.
- The user reported that BTT Lite did not distinguish left and right modifier keys even though their BTT configuration assigns different actions to left/right variants.
- C14 must install over the currently used C12 without resetting the user's edited BTT Lite profile.

Apple/BTT behavior verified:
- Apple documents Magic Mouse one-finger horizontal swipe as page navigation, two-finger horizontal swipe as full-screen app/Space navigation, one-finger vertical movement as scrolling, and two-finger double-tap as Mission Control. Apple does not reserve a two-finger vertical *swipe* on Magic Mouse as a standard navigation gesture.
- Apple HIG recommends preserving familiar standard gestures and responding consistently. Therefore C14 treats a custom two-finger vertical swipe as safe only as an explicit user-defined gesture; using a modifier as a required guard further avoids accidental overlap.
- BetterTouchTool documents `BTTRequiredModifierKeys` for mouse/trackpad gestures and explicitly supports "trigger only if specific modifier keys are pressed". BTT also documents optional left/right modifier differentiation for keyboard shortcuts.
- BTT's advanced modifier mask uses the macOS device-dependent NX modifier bits. These are: left Ctrl 0x1, left Shift 0x2, right Shift 0x4, left Cmd 0x8, right Cmd 0x10, left Option 0x20, right Option 0x40, right Ctrl 0x2000. This matches the user's preset: e.g. Cmd+L advanced value 1048592 carries right Cmd (0x10), while another Cmd shortcut with 1048584 carries left Cmd (0x8).

Compatibility:
- New model fields are Optional so C00-C13 `config.json` files decode without migration or reset.
- Replacing C12 with C14 does not modify `~/Library/Application Support/BTT Lite/config.json`; all user edits made in C12 remain in place.
- C13's runtime fixes are included because C14 is based on C13, but no gesture rule is re-enabled or rewritten automatically.

Left/right modifier changes:
- Added `ModifierSideSet` using the canonical macOS/NX device-dependent modifier bits.
- KeyboardModifierState now tracks side-specific modifier state from flagsChanged while retaining the C12 Fn anti-sticky state machine.
- Keyboard trigger matching honors side identity only when `differentiateModifierSides` is enabled. Without that option, left/right remain interchangeable exactly as before.
- BTT importer reads `BTTShortcutAdvancedModifierKeys` plus `BTTLeftRightModifierDifferentiation`, preserving left/right Command, Option, Shift and Control from imported presets.
- BTT shortcut actions now preserve physical modifier key codes too: left/right Cmd (55/54), Shift (56/60), Option (58/61), Control (59/62).
- Synthetic shortcut actions can carry the side-specific device bits on the key event without generating standalone fake modifier transitions.
- Settings exposes "Distinguish left/right modifiers" for keyboard triggers. Recording a shortcut captures the actual side used and shows L/R in the displayed shortcut.
- Added CI regression coverage for left/right modifier state and the exact NX bit layout.

Modifier-guarded gesture changes:
- GestureTrigger now supports required modifiers, optional left/right side requirements, and left/right differentiation.
- Gesture matching treats modifiers as a guard: if no modifiers are configured, existing gestures behave exactly as before; if modifiers are configured, they must be physically held when the gesture is recognized.
- Settings exposes a "Capture Held Modifiers" control for Magic Mouse/Trackpad triggers. Hold the desired modifier(s), click the control, then configure e.g. Fingers=2 / Swipe / Up or Down.
- The same left/right differentiation checkbox can be enabled for gesture modifiers.
- BTT importer reads `BTTRequiredModifierKeys` and side information for modifier-guarded gestures.
- Added importer regression tests for right Cmd vs left Cmd, side-specific shortcut actions, and a left-Option-guarded two-finger Magic Mouse swipe.

Recommended Magic Mouse layout for the user's new plan:
- macOS: 2-finger left/right = Spaces; 1-finger left/right = page back/forward.
- BTT Lite: old 3-finger left/right Space rules disabled; old 2-finger horizontal page rules disabled.
- Optional custom close/restore: 2-finger Up/Down plus a chosen modifier guard. Do not configure bare 2-finger vertical swipe if accidental activation while manipulating the mouse would be undesirable.


## C15 — BTT-style import browser and concrete action summaries

Status: implemented; macOS arm64 CI validation pending at commit time.

User problem / visual target:
- After importing the BetterTouchTool preset, the flat BTT Lite list made it difficult to see which application scope, trigger and gesture belonged to which action.
- The user supplied side-by-side screenshots of BetterTouchTool and BTT Lite and requested the familiar BetterTouchTool visual structure, especially the application grouping and trigger → action readability.

Changes:
- Reworked Settings into a three-pane browser: application scopes on the left, triggers in the middle and the existing detailed editor on the right.
- The left pane now shows **For All Apps** plus application scopes reconstructed from the imported rules in first-seen preset order.
- Replaced the single category popup with a BTT-like trigger category strip for All / Keyboard / Mouse / Trackpad / Other, with native SF Symbol icons.
- Application scope and trigger category are independent filters, matching the mental model of BetterTouchTool rather than flattening all imported rules together.
- Trigger rows now use a native trigger icon, a concise trigger title on the first line and a BTT-style **Action: ...** summary on the second line.
- Action summaries expose the concrete target when available: e.g. **Run Shortcut: Imgur**, **Toggle Bluetooth Device Connection: Win**, the actual keyboard shortcut, launch target or URL.
- Multi-action rules use the familiar **and N more** form. Rules/actions that are disabled remain visible and are visually de-emphasized instead of becoming ambiguous.
- Gesture rows use a compact title such as **2 Finger Swipe Up**; the device is already communicated by the selected Mouse/Trackpad category.
- New rules inherit the currently selected application scope in the sidebar.
- No configuration migration is required. Existing C12/C14 `config.json` data is only presented differently; trigger/action runtime semantics are unchanged.

Resource impact:
- The new controls exist only while the Settings window is open.
- No new background service, polling loop, database, WebView or runtime framework was added, so idle-agent resource use is unchanged.

Regression coverage:
- Added pure-model checks that concrete Shortcut and Bluetooth targets are present in the browser-facing action summaries.
- Existing importer, keyboard/system shortcut, gesture and packaged-app tests remain in CI.

Retest contract:
1. Install over the existing BTT Lite configuration; do **not** reimport unless explicitly testing import.
2. Confirm the left pane shows **For All Apps** and the application names from the preset (for example Finder / Google Chrome where rules exist).
3. Select Keyboard / Mouse / Trackpad and confirm the middle list changes without losing the selected application scope.
4. Confirm each row is readable as **trigger** on line 1 and **Action: concrete target** on line 2, including Fn shortcuts and Bluetooth/Shortcuts actions.
5. Confirm selecting a row still opens the same editable rule/action configuration on the right.


## TP01 — Define the unmodified Trickpad pilot

Status: complete.

Decision:
- Do not fork or customize Trickpad yet.
- Use upstream Trickpad 0.14.0 unchanged for a real-device pilot.
- Keep this work isolated on branch `trickpad-pilot`; do not merge it into the BTT Lite runtime while the pilot is being evaluated.
- Pin the pilot to upstream commit `e16f7fcd1613b9df944957cbda0e69d8eaf19163` so builds are reproducible.

Gesture mapping:
- Magic Mouse: 3-finger swipe up → ⇧⌘T; 3-finger swipe down → ⌘W; 3-finger click → ⇧⌘V.
- Built-in trackpad: 3-finger click → ⇧⌘V; 3-finger swipe up → ⇧⌘T; 3-finger swipe down → ⌘W; 3-finger double-tap → activate hovered Dock app then ⌘H.
- Trackpad 2-finger swipe left/right are intentionally left to macOS native “Swipe between pages” because Trickpad 0.14.0 only exposes 3–4 finger trackpad swipes. Native left/right behavior matches Page Forward/Page Back.

Resource/installation constraints:
- No Homebrew.
- No local Xcode or Command Line Tools on the user's Mac.
- The Dock helper must be short-lived and installed in `~/bin`; it must not become another resident process.
- CI will build the upstream app and helper.

Files added:
- `experiments/trickpad-pilot/README.md`
- `experiments/trickpad-pilot/config.toml`

Next commit:
- TP02: add CI that builds the pinned upstream source without modifying it, compile the on-demand Dock helper, and package a ready-to-install pilot.


## TP02 — Build the upstream pilot remotely and add the Dock helper

Status: implemented; GitHub Actions validation is triggered by this commit.

Changes:
- Added a dedicated `Build Trickpad pilot` workflow on branch `trickpad-pilot`.
- CI fetches exactly upstream Trickpad 0.14.0 commit `e16f7fcd1613b9df944957cbda0e69d8eaf19163`, runs upstream `scripts/check.sh`, and packages the resulting app without changing Trickpad source.
- The user's Mac therefore needs neither Homebrew nor Xcode/Command Line Tools.
- Added one Objective-C command-line helper for the only required BTT action Trickpad cannot express directly: 3-finger trackpad double-tap over a Dock item → activate that Dock item → send ⌘H.
- The helper is short-lived, has no UI, no launch agent, no polling loop, and is installed as `~/bin/trickpad-hide-hovered-dock-app`.
- Added `install.command`, which installs Trickpad to `~/Applications`, the helper to `~/bin`, and the pilot TOML to `~/.config/trickpad/config.toml`. An existing config is timestamp-backed up first.
- The helper carries a stable ad-hoc designated identifier `local.trickpad.dockhelper` to make its Accessibility identity stable across rebuilds at the same path.
- CI smoke-checks both signatures and the exact required TOML bindings before uploading `Trickpad-Pilot-0.14.0.zip`.

Permissions:
- Trickpad needs Accessibility for its keystroke bindings.
- The short-lived Dock helper separately needs Accessibility because it uses the macOS Accessibility API to identify and press the Dock item under the pointer and then posts ⌘H.

Still intentionally native:
- Trackpad 2-finger swipe left/right remain macOS “Swipe between pages”; Trickpad 0.14.0 has no 2-finger trackpad swipe recognizer.

Next:
- Wait for this workflow to turn green. Do not hand the pilot to the user until the upstream checks, build, signatures, helper compile, and package smoke checks all pass.


## TP03 — Green CI and ready-to-test pilot artifact

Status: complete.

Validation:
- GitHub Actions run `36278333271` completed with conclusion `success`.
- Upstream Trickpad 0.14.0 was fetched at exactly `e16f7fcd1613b9df944957cbda0e69d8eaf19163`.
- Upstream `scripts/check.sh` completed successfully before packaging.
- The upstream Trickpad source was not patched.
- The on-demand Dock helper compiled successfully for Apple Silicon/macOS 15+, received its stable ad-hoc designated requirement, and passed strict code-sign verification.
- Package smoke tests verified both signatures and the exact gesture bindings before upload.
- Artifact `Trickpad-Pilot-0.14.0` was uploaded successfully.

Artifact identity:
- Actions artifact ID: `10917946628`.
- Actions run: `36278333271`.
- Outer artifact SHA-256 reported by GitHub: `037830779de1d006e772548f83fd35f16fe5bde5fb9a7a79fa1022f4c471fd45`.
- Ready-to-install inner ZIP SHA-256 after extraction: `2e42a0b642297e15b4a00e213ba55e1e3828775cddc63027af8f8d05862b38d5`.

On-device test gate:
- No Trickpad source customization should begin until this pilot is tested on the MacBook Air M1.
- First test only the agreed 3 Magic Mouse + 6 trackpad behaviors.
- Trackpad 2-finger left/right remain native macOS page navigation by design.
- If the pilot proves reliable, the next decision is whether the menu-bar/updater/UI footprint is acceptable or whether a minimal custom/headless fork is justified.


## TP04 — Fix repeated swipe actions and Dock hit-testing

Status: implemented from the first real-device pilot report; CI validation is triggered by this commit.

Observed on MacBook Air M1 / macOS Sequoia:
- 3-finger swipe up/down could open or close two tabs from one physical swipe.
- 3-finger double-tap over Dock produced Trickpad's popover: helper exited with code 2.

Root causes:
- The duplicate tab action is not a sensitivity setting. Upstream Trickpad intentionally allows an owning swipe recognizer to repeat while the same contact sequence remains active. Directly binding ⇧⌘T / ⌘W therefore does not guarantee exactly one action per physical swipe.
- The Dock helper used NSEvent.mouseLocation with AXUIElementCopyElementAtPosition. Accessibility hit-testing expects top-left-relative screen coordinates, while NSEvent.mouseLocation follows the AppKit lower-left global coordinate system. The mismatch made the helper miss the Dock item and return exit code 2.

Changes without modifying upstream Trickpad:
- The existing short-lived helper now obtains the pointer through CGEventGetLocation, matching the coordinate orientation expected by Accessibility hit-testing.
- The same already-authorized helper gained two modes: close-once and reopen-once.
- Added two tiny wrapper scripts in ~/bin: trickpad-close-tab-once and trickpad-reopen-tab-once.
- Up/down swipe bindings now call those wrappers. The helper coalesces rapid repeat dispatches from one continuous Trickpad swipe using a 300 ms quiet-window gate, while remaining non-resident.
- The helper path and designated identifier remain unchanged, so the existing Accessibility grant should remain valid after reinstall.
- No Trickpad source code was changed; this remains a test of the upstream application.

Retest contract:
1. Re-run the updated pilot installer over the existing install.
2. Quit BetterTouchTool completely during the pilot so identical BTT gestures cannot add a second action.
3. Reload Trickpad settings.
4. Perform 10 deliberate swipe-up and 10 swipe-down gestures on the device being tested; each physical gesture should create exactly one ⇧⌘T or ⌘W.
5. Put the pointer directly over a Dock app icon and perform the 3-finger double-tap; the old exit-code-2 popover should no longer appear and the target app should activate then hide.


## TP04.1 — Green CI for the first real-device fixes

Status: complete.

Validation:
- GitHub Actions run `36281163234` completed successfully.
- Upstream Trickpad checks passed unchanged.
- The revised short-lived helper compiled and passed strict code-sign verification.
- Package smoke checks verified the one-shot swipe wrappers and all expected TOML bindings.
- Artifact: `Trickpad-Pilot-0.14.0-TP04`, Actions artifact ID `10918654528`.
- GitHub outer artifact SHA-256: `995132509f71230dae197710dd8cd5b666151139f053ddeab7b1f7425284ca57`.
- Ready-to-install inner ZIP SHA-256: `602a5be8b02965ebedbd3ee51e99c161b0017351774e0bfb4a45f9e170659aca`.

Next on-device gate:
- Install TP04 over TP03.
- Keep BetterTouchTool fully quit during comparison.
- Retest swipe up/down single-fire behavior and the Dock double-tap action.


## TP05 — Keep swipe behavior unchanged; fix only Dock double-tap

Status: implemented by explicit user request; CI validation is triggered by this commit.

User correction:
- Do not modify 3-finger swipe up/down behavior. The earlier double-open/double-close observation may have been caused by another program and the user reports the swipes now appear to work correctly.
- Only the 3-finger double-tap Dock action should be fixed.

Changes:
- Restored both Magic Mouse and trackpad 3-finger swipe up/down bindings exactly to the TP03 direct shortcuts:
  - up → ⇧⌘T
  - down → ⌘W
- Removed the TP04 one-shot swipe wrapper scripts from the repository and package.
- Restored the TP03 installer structure; no swipe helper is installed.
- Kept exactly one functional change relative to TP03: the Dock helper now gets the pointer position using Quartz CGEventGetLocation before AXUIElementCopyElementAtPosition. This fixes the coordinate-system mismatch that produced exit code 2.
- Trickpad itself remains unmodified upstream 0.14.0.

Retest contract:
1. Install TP05 over the current pilot.
2. Do not evaluate or tune the 3-finger swipe up/down gestures as part of this change; they are intentionally unchanged.
3. Put the pointer directly over an application icon in Dock and perform the 3-finger double-tap.
4. Expected: the target Dock app is activated and then hidden with ⌘H; no exit-code-2 popover.


## TP06 — Robust Dock-tree lookup; swipes frozen

Status: implemented from the second real-device failure of the 3-finger double-tap helper; CI validation is triggered by this commit.

User direction:
- Treat the current direct 3-finger swipe up/down behavior as the known-good baseline.
- Do not tune, debounce, wrap or otherwise change those swipe bindings.
- Fix only the 3-finger double-tap Dock action.

Observed:
- TP04/TP05 still showed Trickpad's “script binding didn't run” popover with helper exit code 2.
- Exit code 2 means the helper still could not resolve an application Dock item under the pointer.
- Merely switching from NSEvent.mouseLocation to CGEventGetLocation was therefore insufficient on this Sequoia setup.

TP06 change:
- Removed system-wide Accessibility hit-testing from the Dock helper.
- The helper now finds the running Dock process by bundle id `com.apple.dock`, creates an AX application element for that PID, finds Dock's AXList, enumerates its AXDockItem children, restricts matches to subrole `AXApplicationDockItem`, reads each item's AX position/size frame and matches the Quartz pointer position directly against those frames.
- A conservative 14-point nearest-item fallback covers brief Dock magnification/frame-animation lag without jumping to a remote icon.
- The helper remains short-lived and uses the same installed path and designated identifier.
- Magic Mouse and trackpad 3-finger swipe up/down lines remain exactly the direct TP03/TP05 bindings: up = ⇧⌘T, down = ⌘W.
- No Trickpad upstream source is modified.

Retest contract:
1. Install TP06 over the existing pilot.
2. Do not change or retest swipe sensitivity as part of this commit.
3. Put the pointer visibly over an application icon in Dock.
4. Perform the trackpad 3-finger double-tap.
5. Expected: the icon is resolved from Dock's own Accessibility tree, the app is activated, then ⌘H hides it; no exit-code-2 popover.


## TP07 — Stop guessing pointer geometry; use Dock hover state

Status: implemented after TP06 reproduced exit code 2 on the real Mac; CI validation is triggered by this commit.

Why the approach changed:
- Three successive versions tried to infer the Dock target from system-wide hit-testing or from assumed Dock-tree geometry.
- TP06 proved that simply changing coordinates or assuming a direct AXList child is not enough on this macOS Sequoia machine.
- The new primary mechanism is semantic, not geometric: Dock exposes its currently hovered item through `AXSelectedChildren`. This is the same class of mechanism used by established Dock-hover utilities.
- Geometry is now only a fallback and traverses the whole Dock Accessibility tree recursively instead of assuming one fixed hierarchy.

TP07 behavior:
- 3-finger swipe up/down bindings remain byte-for-byte the direct bindings already accepted by the user: up = ⇧⌘T, down = ⌘W. No debounce, wrapper or sensitivity change.
- On 3-finger double-tap the short-lived helper:
  1. resolves Dock PID;
  2. recursively finds a non-empty `AXSelectedChildren`;
  3. accepts only subrole `AXApplicationDockItem`;
  4. performs AXPress on that exact hovered item;
  5. falls back to the item's AXURL / running application activation if AXPress fails;
  6. sends ⌘H after activation.
- If semantic hover resolution is unavailable, a recursive full-tree geometry fallback searches all `AXApplicationDockItem` elements. It does not assume Dock's list is a direct child.
- If the helper still fails, it writes a one-shot diagnostic file to `~/Library/Logs/TrickpadPilot/dock-helper.log` containing the actual Dock PID, selected-child observations, pointer coordinates, discovered Dock-item frames and nearest distance. This prevents another blind rebuild.
- The diagnostic is written only on failure; there is no resident logger or background process.

Retest:
- Install TP07 over the current pilot.
- Test only 3-finger double-tap over an application icon in Dock.
- If it still returns an error, do not redesign again from theory: read `~/Library/Logs/TrickpadPilot/dock-helper.log` from the user's Mac and fix from that concrete runtime data.


## TP07.1 — Green CI for semantic Dock-hover build

Status: complete.

Validation:
- GitHub Actions run `36282200162` completed successfully.
- Upstream Trickpad 0.14.0 checks passed unchanged.
- The revised Dock helper compiled for arm64/macOS 15+, passed strict code-sign verification, and the package smoke tests confirmed the accepted direct swipe bindings remain unchanged.
- Artifact: `Trickpad-Pilot-0.14.0-TP07`, Actions artifact ID `10919067818`.
- GitHub outer artifact SHA-256: `fd1f0623a7ac0a0c0112c09ec5afc2bab638b50e55cd31c8825004aa35361c68`.
- Ready-to-install inner ZIP SHA-256: `e38d208ea336d686ae5967fba4828ac7e52ff8af4f4a2acfea83ca7334fde015`.

Failure-data rule:
- If TP07 still reports an error on the real Mac, do not make another theory-only Dock rewrite.
- Read `~/Library/Logs/TrickpadPilot/dock-helper.log` generated by the failed invocation and base the next fix on that concrete AX tree/hover data.


## TP08 — Accepted combination: TP04 swipe fix + TP07 Dock fix

Status: implemented by explicit user direction; CI validation is triggered by this commit.

Canonical behavior chosen by the user:
- Preserve TP04's fix for Trickpad's repeated 3-finger swipe dispatch. One physical swipe up/down must yield one shortcut only.
- Preserve the two TP04 wrapper files in `~/bin`:
  - `trickpad-reopen-tab-once`
  - `trickpad-close-tab-once`
- Preserve TP07's redesigned 3-finger double-tap Dock handling and its failure-only diagnostics.
- Do not revert the swipe bindings to direct `cmd+shift+t` / `cmd+w`.

Implementation:
- Restored TP04 `config.toml` exactly for swipe bindings on both Magic Mouse and built-in trackpad:
  - 3-finger swipe up → `script:~/bin/trickpad-reopen-tab-once`
  - 3-finger swipe down → `script:~/bin/trickpad-close-tab-once`
- Restored the TP04 installer behavior that installs both wrapper scripts into `~/bin`.
- Restored the TP04 wrapper scripts byte-for-byte.
- The short-lived helper now contains both behaviors:
  - TP04 `close-once` / `reopen-once` 300 ms quiet-window coalescing;
  - TP07 Dock hover resolution using `AXSelectedChildren` first, recursive Dock AX-tree geometry fallback second, plus failure log at `~/Library/Logs/TrickpadPilot/dock-helper.log`.
- There is still only one compiled helper binary in `~/bin`; the two 70-byte wrapper files merely invoke that binary with an argument and are not resident processes.
- Upstream Trickpad 0.14.0 remains unmodified.

Regression gates in CI:
- both wrapper files must exist and be executable;
- both mouse and trackpad swipe bindings must point to the wrappers;
- 3-finger double-tap must point to `trickpad-hide-hovered-dock-app`;
- helper must compile arm64 and pass strict code-sign verification.

On-device retest:
1. Install TP08 over the current pilot.
2. Confirm one deliberate swipe up opens/restores exactly one tab, and one swipe down closes exactly one tab.
3. Confirm 3-finger double-tap over an app icon in Dock activates then hides it.
4. If Dock double-tap still fails, collect only `~/Library/Logs/TrickpadPilot/dock-helper.log`; do not change swipe logic.


## TP08.1 — Green CI and verified combined package

Status: complete.

Validation:
- GitHub Actions run `36282682117` completed with conclusion `success`.
- Upstream Trickpad checks passed unchanged.
- Combined helper compiled for arm64/macOS 15+ and passed strict code-sign verification.
- CI verified both TP04 wrapper scripts exist and are executable.
- CI verified mouse and trackpad 3-finger swipe up/down are bound to the TP04 wrappers, not direct shortcuts.
- CI verified trackpad 3-finger double-tap remains bound to the TP07-derived Dock helper.
- Artifact: `Trickpad-Pilot-0.14.0-TP08`, Actions artifact ID `10919332446`.
- GitHub outer artifact SHA-256: `ef5a6cd4d051b63e6d4becb3b484041d52ba58e6a705642b851666610f6b27e2`.
- Ready-to-install inner ZIP SHA-256: `7c2951b583512cb0fb152fe05ccd8e8bbf2233b54f0e86b2c1ae845e094cfe7e`.

Package inspection after CI:
- `pilot/bin/trickpad-close-tab-once` is present and invokes the compiled helper with `close-once`.
- `pilot/bin/trickpad-reopen-tab-once` is present and invokes the compiled helper with `reopen-once`.
- `config.toml` contains the expected TP04 wrapper bindings for both Magic Mouse and trackpad.
- `three-finger-double-tap` points to `~/bin/trickpad-hide-hovered-dock-app`.

This TP08 package is the current canonical pilot baseline.


## TP09 — Handoff after TP08 Dock double-tap still fails

Status: unresolved; handoff prepared for a stronger adjacent-chat model.

Real-device result:
- TP08 preserves the accepted TP04 one-swipe/one-action behavior.
- TP08 still fails the trackpad 3-finger double-tap Dock action with Trickpad reporting `trickpad-hide-hovered-dock-app` exit code 2.
- Therefore TP07 semantic hover lookup + recursive geometry fallback did not solve the Dock target resolution on this MacBook Air M1 / macOS Sequoia.

Do not change next:
- Keep TP04 `trickpad-close-tab-once` and `trickpad-reopen-tab-once` wrappers and 300 ms coalescing exactly as the current baseline.
- Do not revert up/down swipes to direct Trickpad shortcuts.

Required next diagnostic:
- Read `~/Library/Logs/TrickpadPilot/dock-helper.log` from the real Mac before another Dock implementation change.
- If the log is absent, verify the installed helper, `--check` Accessibility status, and installed TOML bindings.
- No further theory-only Dock rewrite should be made without those runtime observations.

Dedicated handoff:
- `HANDOFF_TRICKPAD_TP08_DOCK_DOUBLE_TAP_RU.md`


## TP10 — Correct the actual requirement: hide the app under the pointer

Status: implemented after the user's explicit clarification on 2026-09-27; CI pending.

The user clarified that three-finger double-tap must hide the application whose
window is under the pointer, not an app icon in Dock. Earlier TP01-TP09 Dock
requirements and the dedicated TP08 handoff were incorrect for this gesture.
Runtime logs showed trusted=yes and valid Dock geometry but no hovered Dock item;
the failure was consistent with using a window gesture away from Dock.

Changes:
- Replace all Dock AX lookup/activation/global Command-H code with Quartz visible
  window bounds + owner PID lookup and NSRunningApplication.hide for that app.
- Select the frontmost ordinary visible window containing the Quartz pointer.
  Exclude desktop elements, nonzero window layers and transparent windows.
- No target outside an app window is a successful no-op; never hide an unrelated
  frontmost app as fallback.
- Hides the whole app, consistent with Command-H, rather than minimizing a window.
- Retain the historical executable path/signing identifier for binding/grant compatibility.
- Preserve TP04 swipe gate and shortcut routines byte-for-byte, as well as both
  wrapper scripts and the entire config.toml. No upstream Trickpad changes.
- Add seven pure targeting tests and CI checks for the preserved TP04 implementation.
- Update README and mark the earlier handoff obsolete.
- No new background process, screen capture, Homebrew or local developer tools.

Validation scope:
CI validates compilation, arm64 signature, targeting cases and swipe preservation.
Actual physical gesture and cross-process hide still require the user's Mac.
Do not claim real-device success from CI alone.

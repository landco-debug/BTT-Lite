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

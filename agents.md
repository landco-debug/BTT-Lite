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

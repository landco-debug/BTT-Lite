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

Status: created on GitHub as the root commit before importing the staged local history.

Changes:
- Created the public `landco-debug/BTT-Lite` repository requested for this project.
- Added this hand-off file first so every later functional commit has an authoritative project log from the beginning.
- No runtime or UI code exists in C00.

Next planned commit:
- C01: configurable native AppKit editor and BetterTouchTool preset importer.

## C01 — Bootstrap configurable AppKit editor and BTT importer

Status: implemented locally; macOS build must be verified by CI after the GitHub repository exists.

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

Next planned commit:
- C02: low-overhead keyboard/system-key event engine and native action executor; keep gesture engine separate.

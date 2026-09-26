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

## C00 — Repository bootstrap and project charter

Status: created on GitHub as the root commit before importing the staged local history.

Changes:
- Created the public `landco-debug/BTT-Lite` repository requested for this project.
- Added this hand-off file first so every later functional commit has an authoritative project log from the beginning.
- No runtime or UI code exists in C00.

Next planned commit:
- C01: configurable native AppKit editor and BetterTouchTool preset importer.

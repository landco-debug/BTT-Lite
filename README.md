# BTT Lite

A small macOS 15+ menu-bar automation agent designed as a focused alternative to BetterTouchTool for a limited, user-configurable set of keyboard, Magic Mouse, trackpad and app-specific triggers.

## Design goals

- Native AppKit UI; no Electron/WebView/embedded browser.
- No database: configuration is one JSON file in `~/Library/Application Support/BTT Lite/config.json`.
- The editor window exists only while the user opens Settings.
- Every rule is editable: enable state, app scope, trigger and ordered actions.
- Multiple profiles are supported; the active profile can be changed, duplicated or deleted.
- BetterTouchTool `.bttpreset` JSON can be imported locally. The repository contains no user-specific preset data.
- Target machine: Apple Silicon, macOS Sequoia (15+).
- No Homebrew and no local Xcode/Command Line Tools are required for the end user: GitHub Actions produces an arm64 `.app` archive.

## Current implementation

The first milestone implements the low-overhead configuration core and graphical editor:

- profile management;
- rule list with Global / Keyboard / Magic Mouse / Trackpad / Applications filters;
- keyboard, gesture, system-key and preserved/unsupported trigger models;
- ordered multi-action rules;
- action editing for all action categories found in the reference BTT preset;
- local import of BetterTouchTool presets without publishing personal commands or device identifiers;
- atomic JSON persistence.

Runtime trigger engines are intentionally separate from the editor so that the always-on process can stay small.

## Build

On macOS with the Apple toolchain:

```sh
./scripts/build-app.sh
```

The output is `dist/BTT-Lite-arm64.zip`.

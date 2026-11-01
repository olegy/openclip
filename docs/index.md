# OpenClip Technical Documentation

Welcome to the **OpenClip** technical documentation hub. OpenClip is a lightweight, high-performance macOS floating popup utility written in Swift (macOS 14.0+). OpenClip Lite is the palette-only variant: a global shortcut reads the selected text (or falls back to the clipboard) and opens a searchable command palette of actions (copy, cut, paste, definition lookups, web searches, custom scripts, and extensions), then executes their platform side-effects.

---

## Quick Start Guide

### Prerequisites
- macOS 14.0 (Sonoma) or later
- Xcode 15.0+ (for building from source)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Building & Running

1. **Clone the Repository:**
 ```bash
 git clone https://github.com/olegy/openclip.git
 cd openclip
 ```

2. **Generate Xcode Project:**
 > **Note:** Run `xcodegen generate` whenever adding or removing `.swift` files.
 ```bash
 xcodegen generate
 ```

3. **Build the Application:**
 ```bash
 xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -destination 'platform=macOS' build | tail -n 10
 ```

4. **Run Unit Tests:**
 ```bash
 xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED"
 ```

5. **Grant Accessibility Permissions:**
 OpenClip relies on macOS Accessibility APIs to read the selection when the palette shortcut is pressed. Grant permission in **System Settings > Privacy & Security > Accessibility**.

---

## Documentation Table of Contents

### System Architecture
- [Architecture Overview](architecture/overview.md) — Module target split (`Core` vs `OpenClip` App) and the Core Architectural Subsystems.
- [Known Debt & Current-State Realities](architecture/known-debt.md) — `UserDefaults` → `SettingsStore` migration, singleton wiring, latent issues.
- [Directory Structure](architecture/directory-structure.md) — Annotated per-file source tree.
- [Action Coordinator & Registry](architecture/action-coordinator.md) — Central wiring, callback mechanics, and ordering policy.
- [Text Selection Subsystem](architecture/text-selection.md) — On-demand selection read at hotkey time, the gate/resolver/strategy retrieval model, and the clipboard fallback.
- [Popup Panel & Placement](architecture/popup-window.md) — `PopupPanel`, the palette/result-card window, `PopupPositioner.spotlightFrame`, and window lifecycle.
- [Logging](logging.md) — the single `Log` surface, category table, and per-subsystem filtering workflow.
- [DMG Installer](dmg.md) — the styled disk image: HTML-rendered background, Retina TIFF, and the Finder layout contract.

### Developer Guide
- [AGENTS.md — Authoring & Packaging Extensions](../Extensions/AGENTS.md) — **Start here.** Self-contained guide: manifest schema, all action kinds, options, requirements, groups, and the result surface.
- [Extending OpenClip Overview](developer-guide/overview.md) — Extension architecture and custom action integration.
- [Extension Package Format](developer-guide/package-format.md) — `.openclipext` bundle structure, `manifest.json` schema, and options definitions.
- [Standalone Snippet Parsing](developer-guide/snippets.md) — Pure header parsing via `OpenClipSnippetParser`.
- [Integration & Automation API](developer-guide/integration-api.md) — The inbound `openclip://` contract: install and command routes, and what is not yet exposed.
- [Code Signing, Hardened Runtime & Releases](developer-guide/signing-and-notarization.md) — Ad-hoc vs Apple Development builds, the entitlements OpenClip grants and refuses, and how `release.sh` publishes a Sparkle update.

### Action Execution Runtimes
- [AppleScript Runtime](runtimes/applescript.md) — `AppleScriptAction` execution, variable injection, and output handling.
- [JavaScript Runtime](runtimes/javascript.md) — `JavaScriptAction` under JavaScriptCore, the `openclip` bridge, and option keys via `SettingKey`.
- [URL Templates Engine](runtimes/url-templates.md) — Parameterized search links using `URLTemplateAction` and `TextPlaceholderEngine`.
- [Shell & Executable Scripts](runtimes/zsh-python.md) — Process execution, environment variables (`OPENCLIP_TEXT`, `OPENCLIP_MATCHED`, `OPENCLIP_ACTION_ID`), and JSON/text stdout parsing.

### User Guide
- [Installation & Onboarding](user-guide/installation.md) — Installing OpenClip, Accessibility permissions setup, and first-launch workflow.
- [Preferences & Customization](user-guide/preferences.md) — Customizing action titles, table icons, ordering, and AI provider setup.
- [Managing Extensions & Custom Actions](user-guide/managing-extensions.md) — Installing remote and local extensions and script snippet actions.

The app follows the macOS system language. English is the source locale; Simplified Chinese, Traditional Chinese, French, and Japanese are bundled in `Sources/OpenClip/Resources/Localizable.xcstrings`.

---

## Core Architectural Principles

OpenClip enforces a strict single-responsibility architecture divided across **Core Architectural Subsystems**:
1. **Settings Subsystem** — [`SettingsStore`](../Sources/Core/Settings/SettingsStore.swift) (Typed `SettingKey` access; a few legacy `UserDefaults.standard` sites remain in the App target).
2. **Action Presentation** — [`ActionCustomizationManager`](../Sources/Core/Actions/ActionCustomizationManager.swift) (Surface-tailored icon and title resolution).
3. **Action Chrome Policy** — [`ActionChrome`](../Sources/Core/Actions/ActionChrome.swift) (UI policy metadata without type checking).
4. **Action Factory** — [`DefaultActionFactory`](../Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift) (Action creation from manifests/snippets).
5. **Action Result Handler** — [`ActionResultHandler`](../Sources/OpenClip/Platform/Effects/ActionResultHandler.swift) (Platform side-effects, pasteboard, and key events).
6. **Action Coordinator & Composition** — [`ActionCoordinator`](../Sources/Core/Actions/ActionCoordinator.swift) (Composition root; wires managers to the registry via `onRegister`/`onUnregister` callbacks).

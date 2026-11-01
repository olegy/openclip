# Text Selection Subsystem Architecture

Nothing reads the selection until a hotkey fires. The palette hotkey (and each per-action hotkey) reads the frontmost app's selection on demand, falls back to the clipboard when there is none, and hands a [`SelectionContext`](../../Sources/Core/Selection/SelectionContext.swift) to the popup. There is no passive selection monitoring.

---

## The Hotkey Read

```
⌥⌘C ──> HotkeyManager.handleTogglePopup
          └── resolvePaletteTrigger
                └── collectTrigger(allowsEmptyText: true, skipsCopyOnCollapsedCaret: true)
                      └── collectTriggerResponse
                            ├── triggerAllowed (AppFilter, identifiable app)
                            ├── CollapsedCaretProbe ──> no ⌘C when the caret is collapsed
                            ├── RuleEngine.resolvePolicies ──> AppPolicyContext
                            ├── PopupWindowController.preparePasteProbe (in parallel)
                            ├── SelectionRetrievalCoordinator.retrieveResponse (OpenSelection)
                            └── clipboard fallback / empty context
        ──> PopupWindowController.show(for:pasteAvailable:)
```

[`HotkeyManager`](../../Sources/OpenClip/Platform/HotkeyManager.swift) registers the palette shortcut (`KeyboardShortcuts.Name.togglePopup`, ⌥⌘C by default):

1. **Toggle and cancel**: a press while a read is still in flight cancels it; a press while the popup is visible hides it.
2. **Gating**: `triggerAllowed(frontmost:)` refuses excluded apps (`AppFilter`) and transient helpers with no bundle ID, name or path.
3. **Collapsed caret**: [`CollapsedCaretProbe`](../../Sources/OpenClip/Platform/Selection/CollapsedCaretProbe.swift) checks, off the main actor with a 0.25 s AX messaging timeout, whether the focused text control (`AXTextField`, `AXTextArea`, `AXSearchField`, `AXComboBox`) reports a zero-length `AXSelectedTextRange` and no selected text. If so, the read runs without the copy fallback, so editors that copy the current line on an empty ⌘C (Obsidian, VS Code) fall through to the clipboard. A missing range counts as unknown and keeps the copy fallback. Per-action hotkeys do not run this probe.
4. **Read**: `collectTriggerResponse` resolves the app's `AppPolicyContext` through `RuleEngine`, starts the paste-availability probe alongside, and calls `SelectionRetrievalCoordinator.retrieveResponse` (through [`OpenSelectionBridge`](../../Sources/OpenClip/Platform/Selection/OpenSelectionBridge.swift)) with `trigger: .keyboardShortcut` and `requireCopyEvidence: false`. A synthetic copy is authorized only while the same app is still frontmost and the request is current; otherwise the read ends as `.targetChanged` or `.cancelled`. HTML, RTF and pasteboard flavors of the result are kept.
5. **Clipboard fallback**: if the read returns no text, the current `NSPasteboard.general` string is used and the context is flagged `isClipboardFallback` (`source == .clipboard`). Actions whose `ActionChrome.requiresLiveSelection` is true (extensions declaring `input: "liveSelection"`) are then left out of the palette by `ActionRegistry`; every other action runs on the clipboard text. `resolvePaletteTrigger` treats files copied in Finder as no clipboard text (`HotkeyManager.clipboardHoldsFiles`).
6. **Empty context**: with neither a selection nor clipboard text, the palette still opens on an empty context for standalone actions (`input: "optional"`). If there are none, `showSearch` shows a "No text selected or on clipboard" toast instead.
7. **Limits**: text over `Constants.maxTextLength` (10 MB) ends the read as `.tooLarge`; whitespace-only text counts as empty.

Per-action hotkeys (`handleActionHotkey`) run on the open palette's context when the popup is visible, and otherwise go through the same `collectTrigger` without empty input.

`resolveSynchronousTrigger` is the synchronous variant used when there is no frontmost app (common during clipboard-manager handoffs): it skips per-app gating and goes straight to the clipboard or an empty context.

Each read logs its outcome under the `selection` category with a trace ID (`SelectionTriggerResponse`, `SelectionReadStatus`); selected text is never logged publicly.

---

## Retrieval: Gate and Strategies

Selection retrieval lives in the `OpenSelection` package; `OpenSelectionBridge` maps OpenClip's Core types (`AppIdentity`, `AppPolicyContext`, `CursorClass`, `TextResult`) onto it and routes its diagnostics into `Log` (`OpenClipDiagnosticsSink`).

1. **Fresh AX snapshot**: `AXElementInspector.inspect()` resolves the focused application, then the focused element of that application (never the system-wide element), raced against `Constants.axReadTimeout` (0.5 s). A hung app yields no snapshot instead of stalling the hotkey.
2. **Gate**: [`SelectionGatePolicy`](../../Sources/Core/Rules/SelectionGatePolicy.swift) rejects AX roles that cannot hold a text selection (`skipRoles`) and cursors that do not suggest a text context (`allowedCursors`; `.unknown` never blocks).
3. **Strategy chain**: one canonical order, `ax-text-control → ax-web-area → menu-copy → keyboard-copy`. The app's [`SelectionRetrievalMode`](../../Sources/Core/Rules/SelectionRetrievalMode.swift) picks the entry point; the first non-blank result wins.

| Mode | Strategy |
| :--- | :--- |
| `ax-text-control` (default) | Reads `kAXSelectedTextAttribute` (falling back to `value` + `selectedTextRange`). No pasteboard side effects. Falls through to the web-area strategy when an embedded web area is detected, then to keyboard copy. |
| `ax-web-area` (browsers) | Reads `kAXSelectedTextMarkerRange` → `AXStringForTextMarkerRange`, re-inspecting up to `webAreaSettleMaxRetries` (6) times `webAreaSettleInterval` (50 ms) apart. Falls back to keyboard copy (e.g. Google Docs canvas). |
| `browser-script` (legacy alias) | Same as `ax-web-area`. |
| `menu-copy` (terminals) | Presses the app's **Edit ▸ Copy** menu item through AX and reads the pasteboard. |
| `keyboard-copy` (code editors, Electron apps) | Synthesizes ⌘C and reads the pasteboard. |

### The copy engine

Both copy modes run through OpenSelection's `PasteboardCopyEngine`: archive every pasteboard item, run the trigger, poll for an advanced `changeCount` with non-empty text (up to `Constants.pasteboardCopyTimeout`, 0.25 s, or `safariPasteboardCopyTimeout`, 0.4 s, for browsers), read it, then restore the archived items before returning. The restore is tagged with the `org.nspasteboard.TransientType` and `org.nspasteboard.AutoGeneratedType` markers so clipboard managers ignore it.

---

## Per-App Policy

[`RuleEngine`](../../Sources/Core/Rules/RuleEngine.swift) resolves an [`AppPolicyContext`](../../Sources/Core/Rules/AppRule.swift) (`retrievalMode`, `denyPaste`, `gate`) from the built-in [`DefaultAppRules.catalog`](../../Sources/Core/Rules/DefaultAppRules.swift). It matches the app's identity (bundle ID, or a `process:` / `path:` identifier for bundle-less apps, with `.*` prefix and `*` wildcards); later rules override earlier ones field by field. There are no user-editable rules.

| Group | Applications | Policy |
| :--- | :--- | :--- |
| `nativeApps` | Native AppKit apps | `ax-text-control` |
| `safariGroup`, `chromiumGroup`, `firefoxGroup`, `arcGroup` | Browsers | `ax-web-area` |
| `keyboardCopyApps` | Code editors, IDEs, markdown and note apps | `keyboard-copy` |
| `menuCopyApps` | Terminal emulators | `menu-copy` |
| `denyPasteApps` | Apps where pasting over a selection is unreliable | `denyPaste: true` |
| default | Everything else | `ax-text-control` |

`denyPaste` feeds `PasteAvailability`, which decides both whether the palette offers Paste/Cut and whether a result is pasted or copied (see [Popup Window](popup-window.md)).

---

## Privacy

- The AX modes never write to `NSPasteboard`; the copy modes restore the previous contents and mark the restore as transient.
- Secure text fields do not expose their selected text through AX.
- Selected text and clipboard content are logged only with private redaction; IDs and outcomes are public.

## Inline Action Match Context

Inline result evaluation receives the same per-action regex match context as running the action. The selection is available as `openclip.input.text`, while `openclip.input.matchedText` and `openclip.input.captures` carry the regex match and capture groups, so inline actions such as Currency Converter can evaluate a value inside a longer selection.

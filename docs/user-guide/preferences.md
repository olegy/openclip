# Preferences & Customization

OpenClip offers customization for pinned palette actions, display labels, custom icons, and AI provider integration through the Preferences window.

---

## Opening Preferences

You can open OpenClip Preferences in these ways:
- Click the OpenClip menu bar icon and select **Settings…**
- Press `Cmd + ,` while the command palette or settings window is focused.
- If the menu bar icon is hidden, open OpenClip again from Finder or Spotlight.

## General

The **General** page configures shortcuts, appearance, launch options, and permissions:

- **Shortcuts**:
  - **Command Palette**: The global hotkey (default `⌥⌘C`) that reads the selected text — or the clipboard when nothing is selected — and opens the palette. Pressing it again closes the palette.
- **Appearance**: the palette's look, shared by the result card and toasts — see [Popup Appearance & Theme](#popup-appearance--theme).
- **Save Location**: Where file results are saved (Downloads by default).
- **App**:
  - **Show Menu Bar Icon**: Displays OpenClip in the macOS menu bar. Turning it off removes the icon immediately without stopping OpenClip or its shortcut.
  - **Start at Login**: Launches OpenClip automatically when you log in.
- **Permissions**:
  - **Accessibility Access**: Required to read the selected text and to paste.

---

## Finding your way around

The settings window is designed with a modern macOS Liquid Glass layout:

- **Translucent Backdrop & Clean Sidebar**: The window features a dark blurred Liquid Glass surface with a fixed-width, borderless sidebar sitting directly on the window background beneath native window controls.
- **Distinctive Icon Tiles**: Every page and action is represented with distinct, colored rounded-square icon tiles for instant visual navigation.
- **Inset Detail Card**: Settings details render within an inset rounded glass card featuring an integrated header with frosted back/forward navigation controls (`⌘[` / `⌘]`), breadcrumbs, and contextual action buttons.
- **Interactive Shortcut Recorder**: Global and action shortcuts can be recorded via a popover with live modifier visualization, dashed key placeholder, and direct key-combination listening.
- **Sidebar Organization**: The sidebar lists the app's pages (General, Palette, Store, About), then, under a static **Actions** heading, one page per kind of action: **AI**, **Built-in**, **Custom** and **Extensions**. Every action has exactly one home among those four, where it is edited.
- **About Page**: Shows **OpenClip Lite**, its version, and under it the **Check for Updates** and **GitHub** links; then automatic extension updates (the Store is checked once a day) and log export. The app itself checks for updates once a day and installs one only when you choose to.

---

## Palette

**Palette** lists every action the command palette can show, in two sections:

```
Settings > Palette
├── Pinned       — opens at the top of the palette, in this order; drag to reorder
└── All Actions  — everything else, by name
```

- Right-click an action and choose **Pin** to add it to **Pinned**; **Unpin** takes it back out.
  At most 10 actions can be pinned — what an open palette shows without scrolling — and **Pin** is
  greyed out once the list is full.
- Each row shows the action's alias and hotkey the way the palette does, its enable switch, and
  where it comes from (AI, Built-in, Custom or the extension's name).
- Clicking a row opens the action's own page, which is where its name, icon, alias, shortcut and
  options are changed. Nothing else is edited on Palette.
- The search field at the top right filters by name, alias, keyword or source.

When nothing is typed, the palette shows the pinned actions first, then the rest with the most
recently used first, then by name. Once you type, the match decides the order
(alias → title prefix → title contains → fuzzy → keywords); pins and recent use only break ties.
Pins are saved under the settings key `action.pinned`.

## AI

The AI provider and the AI actions — see [AI Provider Setup](#ai-provider-setup).

## Built-in

**Built-in** lists the actions that come with OpenClip — Search, Calculate, Define, Add Event, Open Link and Reveal in Finder — each with its switch and a **›** into its page:
the name and icon shown in the palette, the alias and hotkey, and any options the action declares
(Search's engine, for example). **Revert** discards unsaved edits; **Save Changes** applies them.

## Custom

Your own Open URL, Text Snippet, Shell Script and JavaScript actions live on **Custom**: the ones
you made, each with a switch and a › into its editor, then **Create with AI** and a card per kind
to make a new one. An action's page has **Duplicate** and **Delete Action…** in its … menu.

## Store

**Store** browses the extension catalogue. The toolbar carries the search field — the system's, so
it collapses to a magnifier when the window is too narrow for it — a **sort** button (Featured,
Name, Downloads, Recently Added), and a **…** menu holding **Install from File…** (for a
`.openclipext` folder, `.zip` or script you already have) and **Refresh Catalog**.

Sorting reorders the catalogue; it never hides anything. **Featured** is the catalogue's own order,
with the curated showcase on top, and it is the only one that shows the Featured section.

## Extensions

**Extensions** lists the installed packages, each with a switch for the whole package and a › into
its page, plus **Browse the Store**. An extension's page opens with a hero: the extension's icon,
its name, what it does, and its version and author.

The extension's own controls sit in the toolbar, on the same line as the back and forward arrows:

- The **switch** on the right turns the whole package on or off.
- The **…** menu beside it holds **View README**, **Show in Finder** and **Uninstall Extension**.
  Uninstalling asks first, in a banner at the top of the page.

Below the hero are each of the extension's actions with its own switch and a **›** into that
action's settings, and **Update** when the Store has a newer version.

The same toolbar pattern applies to every page that is about one thing: **AI** has its switch
there, and an action's page has its switch plus **Duplicate** and **Delete Action** in the … menu.

---

## Customizing Action Titles & Icons

OpenClip allows overriding the display title and icon for any action without editing code or manifests.

### Display Overrides via `ActionCustomizationManager`
- **Custom Title**: Override the default name displayed in the palette and in Settings.
- **Custom Icon**: Pick an SF Symbol, an Iconify icon, or a custom image from the icon picker.

All overrides are managed via [`ActionCustomizationManager`](../../Sources/Core/Actions/ActionCustomizationManager.swift) and stored persistently in `SettingsStore`.

### Action Result Delivery & Click Behavior
When an action produces text output (e.g. transformations, dictionary definitions, calculations):
- **When finished**: Configurable per action in each action's settings page (**Show in card**, **Paste**, or **Copy**). By default, each action uses the author's recommended delivery mode (e.g. **Show in card** for Define, or **Paste or Copy** for text actions that use the standard default).
- **Secondary click (Right-click / ⇧-click)**: Follows the universal **Clipboard Invariant** — a secondary click copies the result to the clipboard (or renders in a card if the primary action was copy), allowing you to copy output without changing the default paste behavior. Explicitly declared secondary outcomes continue to override.

---

## Popup Appearance & Theme

The **Appearance** card on the **General** page styles the palette, the result card and toasts.

### Popup Theme
- **Popup Theme** — **Classic** (solid color themes) or **Glass** (a frosted material surface: Liquid Glass on macOS 26+, a standard frosted material on macOS 14–15).
- **Color Mode** — **System**, **Light**, or **Dark**. This is shared by both themes (Glass adapts to it too — Glass is a material, not a color). A pinned mode forces the popup's `colorScheme` so the material *and* the content colors flip together.
- **Notification Size** — the size of toasts, on a five-step scale.

> [!NOTE]
> The Liquid Glass effect requires macOS 26+. On macOS 14–15 the Glass option renders as an `.ultraThinMaterial` frosted surface.

---

## AI Provider Setup

To order a frequently used AI preset on its own, open **Actions**, expand **AI Tools**, and drag
the preset between the top-level actions. Its position is saved. To return it to the group, drop
it onto the **AI Tools** row. Presets moved out of the group still appear in the palette, and
their existing enable switches, aliases, and hotkeys keep working.

The switch next to **AI Tools** in **Actions** hides the group and its remaining commands without
turning off AI or any presets moved out of it. Right-click the group and choose **Ungroup** to
move all its commands out, or use **Remove from Group** on an individual command. An empty group
disappears from the Actions list. To restore it, right-click a standalone AI command and choose
**Add to Group → AI Tools**. You can then drag more commands onto or inside the group. The palette
lists the group's commands directly.

Select a preset under **AI → AI Actions** to edit its icon, display name, keyboard shortcut,
search alias, and prompt. Changes save automatically. These settings follow the preset whether it
is inside AI Tools or not. **Add Custom AI Action** also offers these controls before creation. They are saved
when you click **Add Action**, which opens the editor for the new preset. Cancelling discards the
draft, including its shortcut and alias.

OpenClip includes an AI assistant overlay that processes text selections using local or cloud AI models.

Select **AI** in the sidebar (the first row under Actions) to turn AI Tools on or off and configure your provider:

| Provider | Description | Setup Requirements |
| :--- | :--- | :--- |
| **Apple Intelligence** | On-device macOS intelligence framework | macOS 26.0+ on Apple Silicon with Apple Intelligence enabled |
| **Ollama (Local)** | Privacy-focused local LLM execution | Running Ollama instance (`http://localhost:11434`) |
| **Cloud AI (OpenAI / Claude / Gemini / DeepSeek / Groq / OpenRouter / Custom)** | Cloud API language models | Valid API Key stored in the login Keychain |
| **Browser Redirect** | Opens AI query in browser | No API key required |

With the Ollama preset, OpenClip asks reasoning models (e.g. Qwen 3.5, DeepSeek-R1) to skip their thinking pass, so results appear in seconds instead of minutes. The CLI presets do the same where the tool exposes a switch: Claude Code runs with `MAX_THINKING_TOKENS=0` and Codex CLI with `-c model_reasoning_effort=none`. GitHub Copilot and custom commands offer no "off" level, so they are left at their defaults.

### Ask AI from the search palette

Anything you type into the command palette (⌥⌘C) that matches no action is offered to AI instead of a "No matches" notice:

- **Ask AI: “…”** runs your text as an instruction on the selected text — select a paragraph,
  type `rewrite to slovak`. Press **⏎** (or ⌘1) to see the answer in the result card, with a
  diff of what changed, then paste or copy it. Press **⇧⏎** and the answer **replaces the
  selection** the moment it lands instead (a "Replacing…" toast shows meanwhile; if the app can't
  paste, or you've switched apps, the answer is copied).
- **Save as AI tool** (⌘2) keeps the instruction as a custom AI action and runs it the same way.
  From then on it appears in the palette by name, in the AI Tools group, and under
  **Settings › AI › AI Actions**, where opening it renames it, edits its prompt, or deletes it.
- Your **recent instructions** are palette rows too: type any part of one (`slo` finds
  `rewrite to slovak`) and run it with ⏎ or ⇧⏎ like the Ask AI row. Eight are kept; a saved
  instruction leaves the list.

The rows appear only while AI is switched on; the instruction is sent to whichever provider is
configured above.

### Refine an answer in the result card

Every AI result card has an instruction field above its Copy and Paste buttons. Type what to
change — `shorter`, `more formal` — and press **⏎**: AI runs on the current answer and the card
updates in place. The diff always compares your original selection with the latest answer, so
after five follow-ups you still see the net change. Each follow-up also sees the session so far — the
original selection and what you asked before — as context, so "keep the greeting" or "same tone
as before" works. Chain as many refinements as you like; Paste always pastes the latest answer
over the selection. ⏎ on an empty field pastes as before.

### AI Settings Channel
AI settings are managed through `AIServiceManager` and isolated to ensure security and privacy.

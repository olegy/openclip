# Installation & Onboarding Guide

OpenClip Lite has no published releases or Homebrew cask: you build it from source. This guide covers building, granting permissions, and the first-launch onboarding.

---

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later.
- **Build tools**: Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- **Permissions**: Accessibility, to read the selected text when you press the palette shortcut.

The interface follows the macOS system language. English, Simplified Chinese, Traditional Chinese, French, and Japanese are bundled.

---

## Building

```bash
git clone https://github.com/olegy/openclip.git
cd openclip
./scripts/package_app.sh   # Release build -> build/OpenClip.zip + build/OpenClip.dmg
```

Open `build/OpenClip.dmg` and drag `OpenClip.app` into `/Applications`. Or run
`./scripts/install.sh`, which builds the Release app, replaces `/Applications/OpenClip.app` and
launches it. Settings and `~/.openclip` are kept: the bundle ID is the same.

Builds are signed ad-hoc by default, which needs no Apple Developer account. See
[Code Signing, Hardened Runtime & Notarization](../developer-guide/signing-and-notarization.md)
for signing with a local certificate (keeps the Accessibility grant across rebuilds) or a
Developer ID.

---

## Granting Accessibility Permissions

OpenClip uses the macOS Accessibility APIs (`AXUIElement`) to read the selected text when you press the palette shortcut.

```
System Settings ---> Privacy & Security ---> Accessibility ---> Enable OpenClip
```

1. On first launch, OpenClip prompts you to grant Accessibility permission.
2. Click **Open System Settings**.
3. Navigate to **Privacy & Security > Accessibility**.
4. Toggle the switch next to **OpenClip** to **On**.

Both permissions can also be granted later from **Preferences → General**.

> [!NOTE]
> OpenClip reads the selection only when you press a shortcut. No keystrokes or selection histories are logged or stored.

---

## First-Launch Onboarding Workflow

When launched for the first time, OpenClip presents a 3-step onboarding wizard:

1. **Welcome**: How the command palette works — select text, press the shortcut, pick an action; with nothing selected, the palette works on the clipboard.
2. **Access**: Accessibility permission check.
3. **Extensions**: Recommended extensions (translations, word count, speech) with one-click installation.

Onboarding can be skipped at any step. Open the palette anytime with the global shortcut (**⌥⌘C** by default), configure AI providers in **Preferences → AI**, and change the theme in the **Appearance** card of **Preferences → General**.

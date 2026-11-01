<div align="center">
  <img src="./assets/app-icon.png" alt="OpenClip Lite" width="80" height="80" />
  <h1>OpenClip Lite</h1>
  <p>A stripped-down, modified build of <a href="https://github.com/ganeshmshetty/openclip">OpenClip</a> for personal use.</p>
</div>

OpenClip Lite keeps only OpenClip's command palette: select text in any app (or leave the
clipboard as the input), press the palette shortcut, and run an action on it. Everything else —
features, extensions, runtimes, AI — is the original project's; see the
[OpenClip repository](https://github.com/ganeshmshetty/openclip) for what it can do.

It is not a fork that tracks upstream: changes from the original are ported by hand, and only
when they are useful here.

## Differences from OpenClip

- **Palette only.** No selection action bar: nothing reads the selection or appears until the
  palette shortcut is pressed. The palette and its result card open centered on the screen with
  the mouse (Spotlight-style).
- **Palette footer** shows where the text comes from (selection or clipboard, switchable) and the
  start of that text. Files copied in Finder do not count as clipboard text.
- **Palette rows** show the action's alias, hotkey and ⌘-number.
- **A collapsed caret means no selection:** the palette sends no ⌘C then, so editors that copy
  the whole line (Obsidian, VS Code) fall back to the clipboard.
- **Capture Text** copies the recognized text and confirms it with a notification. It runs only
  from its own shortcut, which has no default.
- **Settings:** no Customize page (theme, color mode and notification size are in General), no
  App Rules, no "Show as" for actions. General shows the Screen Recording permission that
  Capture Text needs.
- **Actions in Settings:** one home per kind of action — AI, Built-in, Custom, Extensions — and a
  Palette page that lists them all. No action groups and no drag-to-order: pin up to 10 actions to
  the top of the palette; the rest follow by most recent use.
- **Menu bar menu** has only Settings and Quit: no Actions submenu and no pause (the
  `openclip://` URL scheme has no pause either).
- **Updates** come from this repository's GitHub Releases through Sparkle, never from the
  original's feed: checked once a day, installed only when you choose to (About → Check for
  Updates). Extensions are checked once a day too. The version is the original's plus a Lite revision (e.g. `1.9.2-lite.1`).
- **Bundle ID** is `com.olegy.openclip`, so Lite installs next to the original OpenClip.

## Building

macOS 14+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/olegy/openclip.git
cd openclip
./scripts/install.sh       # Release build -> /Applications/OpenClip.app (replaces it), then launch
./scripts/test.sh          # tests
./scripts/package_app.sh   # Release build -> build/OpenClip.zip + build/OpenClip.dmg
```

Releases are signed with a free Apple Development certificate and are not notarized. After
installing one by hand from [Releases](https://github.com/olegy/openclip/releases), clear the
download quarantine once; updates after that arrive through Sparkle:

```bash
xattr -dr com.apple.quarantine /Applications/OpenClip.app
```

More in [AGENTS.md](AGENTS.md) and the [docs](docs/index.md).

## License

[AGPL-3.0](LICENSE). OpenClip © 2026 Ganesh M and OpenClip Contributors; this is a modified
version of it. See [NOTICE.md](NOTICE.md).

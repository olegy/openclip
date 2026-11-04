# Changelog

What changes in each OpenClip Lite release. `scripts/release.sh` publishes the section of the
version being released as the GitHub release notes and as the notes in the update window, and
refuses to release a version without one. Newest first; one `## <version>` heading per release.

## 1.9.2-lite.4

- Capture Text is removed, so OpenClip no longer asks for the Screen Recording permission;
  Accessibility is the only one it needs. You can remove OpenClip from System Settings →
  Privacy & Security → Screen & System Audio Recording.

## 1.9.2-lite.3

- The palette shortcut works while another app's floating panel has keyboard focus (a Tinycast
  Note or palette, and other panels that take focus without activating their app). It reads the
  selection in that panel, or opens on the clipboard when nothing is selected, instead of doing
  nothing.

## 1.9.2-lite.2

- The cloud AI key and secret extension options are stored in the login Keychain instead of the
  plain-text file `~/.openclip/secrets.json`. Existing values are not migrated: enter them again,
  and delete the old file.

## 1.9.2-lite.1

Based on OpenClip 1.9.2; only the fixes below were ported from 1.8.2 to 1.9.2.

- Capture Text keeps the app you captured from in focus, so full-screen windows and Safari
  Picture in Picture stay put. Recognized text keeps Vision's line order across columns, and
  failures name their cause.
- Search and URL actions open in the source browser only for http(s) links; custom schemes such as
  `goodlinks://` no longer trigger the browser's "allow this website to open…" prompt.
- Brave Origin is recognized as a browser, and Firefox private-window searches open in the private
  window.
- The AI provider you saved is no longer overwritten when the app launches.
- Uninstalling an extension group also clears its sub-actions' saved options.
- Extensions are reloaded from filesystem events instead of polling the folder while idle.
- Smaller app and disk image.

## 1.8.2-lite.5

First release of OpenClip Lite, based on OpenClip 1.8.2.

- Command palette only: no selection action bar, and nothing reads the selection until the
  palette shortcut is pressed.
- Spotlight-style palette and result card; the footer shows whether the text comes from the
  selection or the clipboard.
- Settings: AI, Built-in, Custom and Extensions pages, and a Palette page to pin up to 10 actions
  to the top of the palette.
- Menu bar menu with only Settings and Quit.
- Updates from this repository: checked once a day, installed only when you choose to.

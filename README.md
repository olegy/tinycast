# Tinycast Lite

A personal build of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar — a tiny, fully
native macOS launcher — with its own features and fixes on top, its own releases and its own
updates. It is not affiliated with upstream; report upstream bugs to upstream only if they reproduce
there.

What is different from upstream is listed in [CHANGELOG.md](CHANGELOG.md). SwiftUI and AppKit, zero
third-party dependencies, macOS 26 or later.

<p align="center">
  <img src="docs/screenshot.png" alt="Tinycast command palette" width="720">
</p>

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).
- **Search Files** — open files and folders from the folders you choose, through Spotlight, with no
  index of our own.
- **Dictionary** — look a word up with the Define Word command, or define whatever you typed from the
  launcher's fallbacks, read from the Mac's own dictionaries.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Calculator** — do math, unit, live currency and crypto conversions inline, right in the palette.
- **Quicklinks** — turn a URL, search, file or deeplink into a command, with placeholders for typed
  input, the clipboard or the date.
- **Apple Shortcuts** — search and run the shortcuts you built in the Shortcuts app, with aliases and
  global hotkeys.
- **Snippets** — reusable Markdown templates with dynamic placeholders, arguments, nested references
  and optional keyword expansion.
- **Custom commands** — run named shell commands through fuzzy search or their own global hotkeys.
- **Window management** — 34 Rectangle-style actions: halves, quarters, thirds, sizing, nudging,
  display moves, fullscreen and Spaces.
- **System actions** — lock, sleep, restart, empty trash, toggle appearance, Bluetooth, mute, hidden
  files, and more.
- **Calendar and meetings** — your next meeting on the empty palette and in the menu bar, one key to
  join it, or let it join itself.
- **Notes** — an unlimited collection of plain Markdown files in one floating editor, searchable from
  the palette and rendered as you write.
- **Emoji picker** — a searchable emoji grid, one keystroke away.
- **AI chat** — use your own key or an installed AI account: ask Quick AI from the palette, or keep
  longer conversations in the AI Chat window, with a searchable, pinnable history. Off out of the box,
  like every AI feature.
- **Quick Actions** — fix grammar, rewrite, translate or summarize the selected text in any app.
- **Raycast extensions** — run the ones you already have natively, rendered as SwiftUI.
- **Backup and import** — export your settings to a file, or import your setup from Raycast.

## Install

Download `Tinycast-<version>.zip` from [Releases](https://github.com/olegy/tinycast/releases),
unzip it and move `Tinycast.app` to `/Applications`. Builds are for Apple silicon and are not
notarized, so clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/Tinycast.app
```

After that Tinycast updates itself from this repository's releases.

## Permissions

**Accessibility** — needed when Tinycast pastes or expands text into another app, and the only
permission snippet keyword expansion needs. You're prompted when you first use a feature that needs
it; grant access in **System Settings → Privacy & Security → Accessibility**. Snippets ship
disabled, and keystrokes are matched locally, never stored and never sent anywhere.

## Using it

1. Open **Settings → General** and record a global shortcut to summon Tinycast.
2. Press it anywhere → the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → Shortcuts** — search an app or custom command and record a global shortcut.
5. **Settings → Snippets** — enable the feature, then create templates with expansion keywords.

## Building from source

```sh
./Scripts/install.sh       # Release build → /Applications/Tinycast.app, launch
./Scripts/run-tests.sh     # the test harnesses
./Scripts/release.sh       # publish a release (needs a CHANGELOG.md section)
```

See **[docs/development.md](docs/development.md)** for the toolchain and
**[docs/release.md](docs/release.md)** for versions and releases. **[docs/](docs/README.md)** indexes
everything else.

## License

[AGPL-3.0](LICENSE), like upstream. Copyright © 2026 Abue Ammar; Lite changes © 2026 olegy.

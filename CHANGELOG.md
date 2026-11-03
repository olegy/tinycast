# Changelog

What is new in each Tinycast Lite release. The update window shows the section of the version it
offers.

## Next

### Removed

- **Dictation** is gone, along with its settings, the microphone button in AI Chat and the
  microphone permission.
- **Hyper Key** is gone.
- **Raycast import** is gone.
- Commands cleanup.

### Settings

- **About** is cleaned up.

### Notes

- **Text Size.** A slider in Settings > Notes makes a note's text larger, in four steps from today's
  size up to 23 points. Headings grow with it; the window's title and footer stay as they are.
- **Show Character Count** can now be turned off in Settings > Notes.
- **Lighter headings and roomier lines.** Headings are semibold and closer to the body's size, so a
  second-level heading no longer reads like a first, and lines have more space between them.
- **Inline code** in a note sits on a rounded chip with room on both sides, in slightly smaller type.
- **Selected text in a note** is highlighted in the system's highlight colour instead of grey.
- **Fit Window to Text** in Settings > Notes can be turned off, so the note window keeps the
  width and height you set instead of growing and shrinking with the text.
- **⌘D selects the word** under the caret, including when the caret sits right after it.
- **⌘Z works on any keyboard layout.** Undo, redo and the formatting shortcuts in a note, AI
  Chat's composer and the other text areas no longer stop working while non-Latin layout is active.
- **Pasting a list item into an empty one** no longer doubles its bullet.
- **The caret stays after a list bullet.** Moving to the start of a list line with the keyboard
  stops where a click would, so Backspace removes the bullet instead of joining the line to the one
  above.
- **Standard window.** Settings > Notes > Window can make the note an ordinary window that other
  apps cover and that stays on its own Space, instead of floating above everything.
- **Paper.** The note can be written on Glass, as before, Frosted, Solid, Cream or White, and the
  first three take an optional tint.
- **Show Title Bar Buttons** can be turned off, leaving a slimmer title bar with just the window
  buttons and the note's title.
- **⌃⌘↑ and ⌃⌘↓ move a list item** up or down among its siblings, nested items with it.

## 0.12.1-lite.1

First Tinycast Lite release, based on [Tinycast 0.12.1](https://github.com/abue-ammar/tinycast/releases/tag/v0.12.1).
Tinycast Lite is a separate app with its own settings and permissions, and it updates itself from this repository's releases.

Most of the changes below come from [Tinycast Space](https://github.com/sermelipharo/tinycast-space), collected from several community forks.

### Launcher and search

- **Alias + Space opens an entry.** Type an exact alias and press Space: a command with arguments
  jumps to its first field, an extension command with optional arguments opens so the rest of what
  you type goes into its own search bar (`brew` → Search Homebrew), and anything else runs. A
  backslash before the Space types a plain space instead.
- **Alias + Tab** does the same as alias + Space. Tab on anything else works as before.
- **Change Alias and Change Shortcut in ⌘K.** Every launcher entry, extension commands included, can
  be given an alias or a shortcut in place, without opening Settings.
- **⌘1–⌘9 run search results.** With a query typed, ⌘N runs the Nth row as Return would; holding ⌘
  shows the numbers.
- **The palette shortcut hides the palette on any screen**, and the next press brings back the
  screen you left.
- **Typo-tolerant search.** When a query of four letters or more matches nothing, Tinycast tries
  again allowing a typo or two. Queries that already match rank exactly as before.
- **Copy Deeplink.** Every entry's ⌘K menu copies a `tinycast://` link that runs it from anywhere —
  a script, another launcher, a note.
- **Show Info in Finder.** ⌘I on an application, or *Show Info in Finder* in its ⌘K menu, opens
  Finder's Get Info window.
- **Escape pops to root.** With "Navigate back or close window", Escape (or the back chevron) on a
  screen with no step back closes the palette and returns to the root search, so a screen opened by
  its own shortcut no longer comes back on every summon.

### Quick Actions

- **Quick Actions open on a palette screen** instead of a floating panel. The text — the selection,
  else the clipboard — is shown on top and can be edited; Return runs the action and the reply
  streams below. Return then pastes the reply into the app you came from, ⌘Return copies it, ⌘E edits
  the text again, and Escape stops a running reply.
- The model, effort or language can be changed per run in the screen's header.

### Appearance

- **Raycast themes.** Settings → General → Appearance has a light and a dark theme slot, filled from
  the ray.so catalog or from imported themes, with a live preview of the theme under the pointer. The
  *Theme* command switches themes from the palette, previewing each as you move through the list.
  `raycast://theme` links — from ray.so, the clipboard or an extension — ask whether to use or just
  add the theme. *Theme background* sets how strongly the palette shows the theme's gradient.
- **Hyper glyph for another app's Hyper key.** With Hyper Key set to None, *Show ✦ for another app's
  Hyper key* still shows Karabiner- or Hyperkey-style chords as ✦.
- **Window corners match macOS windows.** The palette, Notes, dialogs and settings editors are rounded
  like a regular window instead of twice as much.
- **Confetti**, as a system action and as `raycast://confetti`.

### Raycast extensions

- **⌘Return runs an action panel's second action**, as in Raycast; the ⌘K panel labels the first two.
- **Selectable Detail markdown.** All text in an extension's Detail view can be selected and copied;
  code blocks get a frame with their language and a Copy button.
- Deeplinks pass `context` to the command they open; forms focus their `autoFocus` field; icons with a
  `@dark` variant use it on a dark background; ↑/↓ through long extension lists is faster.
- More extensions work:
  - **Google sign-in** for clients without a secret (2FA Code Finder's Gmail sign-in and others).
  - **Google Translate** and other extensions that bundle undici.
  - **OAuth sign-in through raycast.com/redirect** no longer ends in "Application error".
  - Extensions built on `got`, and those that run command-line tools: a missing tool reports a normal
    "not found" error, and tools are looked up on the extension's own `PATH`.

### Clipboard and snippets

- *Images Only* in Clipboard History includes copied image files, and *Files Only* leaves them out.
- *Save as Snippet* (⌘S) in Clipboard History turns a text entry into a new snippet.
- Search Snippets: *Copy to Clipboard* (⌘Return) fills in a snippet and copies it; *Show in Finder*
  moves to ⌘F.

### Fixes

- A quicklink that starts with a placeholder, such as `{clipboard}`, opens instead of failing.
- Open Trash opens the Trash instead of the home folder.

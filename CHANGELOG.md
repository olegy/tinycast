# Changelog

What is new in each Tinycast Lite release. The update window shows the section of the version it
offers.

## Next

### Removed

- **Calendar** is gone completely: the meeting card on the empty palette, Join Next Meeting, My Schedule, Create Event, Copy Meeting Link, Open in Calendar, meeting details, meetings in launcher search, auto join and the camera preview before a meeting, the calendar menu-bar item, the Calendar settings pane and the Calendars row in Permissions. Tinycast no longer asks for calendar access. Its leftover settings, shortcuts and the `calendar` section in `settings.json` are cleaned up on first launch; My Schedule leaves the compact bar.

## 0.12.8-lite.3

### New

- **Snippets** are back, rebuilt around your own Markdown files. Add one or more folders in Settings → Snippets, then Search Snippets finds a file by its name, `keywords` and subfolder names, and previews it with highlighted code. ↵ copies it; ⌘↵ pastes a one-line snippet straight into the app you were in. Create, edit, move between folders and delete from the palette; editing changes only what you edited, so other frontmatter stays as it was. External changes show up on their own.

### Changes

- **The round menu button** at the bottom left of the palette is gone. Settings stays on ⌘, and Quit in the menu-bar icon; **Changelog** moves to Settings → About, next to GitHub, and opens this repository's releases.
- **The ⌘K Actions menu** has the same corner radius as the palette.
- **Code blocks** in Snippets, AI Chat and Quick Actions have smaller corners and no longer wrap: a long line scrolls sideways.

## 0.12.8-lite.2

### Removed

- **Dictation** is gone, along with its settings, the microphone button in AI Chat and the
  microphone permission.
- **Hyper Key** is gone.
- **Raycast import** is gone.
- **Notes** are gone completely.
- **Snippets** are gone completely: keyword expansion, the Snippets pane and its commands, snippet shortcuts and links, the backup category and *Save as Snippet* in Clipboard History. Quicklinks keep every placeholder they had. Their leftover settings, and the `snippets` and `notes` sections in `settings.json`, are cleaned up on first launch.
- Commands cleanup.

### Settings

- **About** is cleaned up.

### Fixes

- **Form fields keep their focus.** A text field in a launcher form no longer reports losing focus
  each time the form redraws while you type in it.

### From upstream Tinycast 0.12.8

Everything from upstream up to 0.12.8 that applies to Lite. Its update signing, update pill,
Notes, Dictation and Hyper Key changes are left out.

- **Compact mode is the default**: a glass search capsule with up to four shortcut buttons, chosen
  in Settings → General → Compact Shortcuts and reachable with the arrow keys. *Show favorites in
  compact mode* is gone.
- **Deeplinks for built-in commands.** Every row that takes a hotkey also runs by
  `tinycast://<kind>/<id>`; ⇧⌘C copies a row's link. Links can carry input, open Settings tabs and
  saved chats, and ask once before acting outside Tinycast.
- **Files and folders as favorites** in the launcher.
- **Show animations** in General settings turns the interface's motion off.
- Opening Tinycast from Finder or Spotlight shows the launcher, and a finished update says so.
- **Window management:** move-to-edge commands, fullscreen windows move between displays, and new
  display-move options.
- **Calculator:** natural-language dates, times in other zones, compound rates and split bills.
- **AI:** custom request headers for API connections, an *Expand thinking* setting, OpenAI MCP tool
  calls fixed, OpenCode uses Tinycast's MCP servers, and Apple Intelligence chats send no instructions.
- **Clipboard history** records HTML-only and RTF-only copies.
- **Extensions:** web OAuth keeps its state through the redirect page, sign-in finishes when
  cancelled, missing preferences can be set directly, and more Node APIs work (`os.networkInterfaces`,
  AES-GCM, `SharedArrayBuffer`, process and file owners).
- Fixes: Volume Up/Down on devices with an off-grid level, the running dot after an app quits,
  calendar events open in the default calendar app, translation language pairs, onboarding language,
  a waiting shell command's prompt, the Toggle System Appearance message, a text area crash, and a
  batch of lifecycle and data-safety bugs.

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

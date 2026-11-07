# Snippets

A snippet is a Markdown file in one of the user's own folders — often an Obsidian vault set aside for
them. Snippets are searched and picked by hand, then copied or pasted; nothing expands by keyword.
The model is the Raycast extension Snippet Surfer, which this feature replaces.

The feature ships **off**. **Settings → Snippets** carries the switch, its launcher-visibility
companion, the folders, the excluded folders and the app Open in Editor uses. Off is fully off: no
scan, no watcher, no Search Snippets or Create Snippet command.

## Invariants

- **The files are the source of truth, and a user's file is never rewritten whole.** Saving changes
  only what the editor changed: the one `keywords:` line of the frontmatter, the content after it, the
  file name. Every other byte — other frontmatter keys, the blank line after the fence, CRLF line
  breaks, the trailing newline — stays as it was. `SnippetDocument` is the only place that edits text,
  and `snippets-test` checks the bytes around every edit.
- **Nothing a write replaces is lost.** A file another snippet's save, rename or move would replace
  goes to the Trash first, and only after the user confirms. Delete moves to the Trash. A body edit
  writes in place, atomically, with no Trash copy.
- **A disk edit made while the editor was open survives.** The editor keeps the text it opened with;
  a save that finds the file changed asks first, and even then writes only the edited fields.
- **The index holds metadata, never bodies.** `SnippetStore` keeps name, `keywords`, folder tags, date
  and size per file. A scan reads only the head of a file — up to the closing frontmatter fence, 64 KB
  at most — and reuses an entry whose date and size are unchanged. A body is read when a snippet is
  shown, copied, pasted or edited, one file at a time.
- **Search is strict.** Each query word must be part of a word of the file name or a tag, all words
  must match, case aside. Never fuzzy, never the body: Snippet Surfer dropped Raycast's fuzzy match
  because it found `chat` in unrelated names.
- **↵ copies, ⌘↵ pastes only a single line.** `SnippetClipboardText` decides both; see below.
- **`Model/` is Foundation-only**, compiled by `snippets-test` with the scanner and the writer.

## Files and folders

Every `.md` file under a snippets folder, at any depth, is a snippet; anything whose name starts with
a dot is skipped, as are folders matching **Excluded Folders** (File Search's ignore syntax, no
defaults). All folders are equal; a file found under two of them is listed once.

Tags are the words of the `keywords` frontmatter value plus each subfolder between the root and the
file (`ruby/rails/auth.md` → `ruby`, `rails`), lowercased. `keywords` counts only as a plain string;
a list, a block or a frontmatter that is not a mapping is ignored, and the file is still a snippet.

A `.vault.json` at a folder's root may name it and give it an icon: `{"name": "Work", "icon":
"hammer"}`. The icon is an emoji or an SF Symbol name; anything else shows the folder symbol.

## Live index

`SnippetStore` lives on `AppCore`. It loads the last scan from `snippets-index.json` in Caches at
once, rescans, and watches the folders with FSEvents; any event triggers another rescan, which only
stats unchanged files. ⌘R rescans by hand and reports read failures again.

## Copy and paste

| Content | ⌘↵ pastes | ↵ copies |
| --- | --- | --- |
| One line of text | the line | the line |
| One fenced block holding one line, nothing else | the code line | the code line |
| One one-line block with prose around it | the code line only | everything |
| One multi-line block, nothing else | — | the code, without fences |
| Several blocks, or several lines of prose | — | everything |

Fences are CommonMark's: three or more backticks or tildes, up to three spaces of indent, closed by
the same character at least as long. Copy is unmarked, so it enters Clipboard History; paste goes
through `Paster.pasteString` like Clipboard History's own. Where ⌘↵ cannot paste, it says so in a HUD
and the actions menu leaves the row out.

## Screens

**Search Snippets** lists the matches newest-changed first beside a preview rendered by
`ChatMarkdownText`, so code blocks are highlighted and carry their own Copy button, and its text
selects and copies with ⌘C. The preview's tag line shows folders as `/folder`, then keywords as
`#word`. A copy, paste, Copy Path, Open in Editor, move, or a click in the preview lifts the snippet to
the top the next time the palette hides (`SnippetCoordinator.paletteDidHide`, which keeps a restored
list's selection on the same snippet): `SnippetStore.noteUse` keeps the time in memory only, so the
file's date is untouched and a relaunch forgets it. A click selects; a double click copies. Closing the editor reselects the edited or created
snippet wherever the rescan put it. Actions: Copy (↵), Paste (⌘↵), Edit (⌘E), Create (⌘N), Move to another folder,
Open in Editor (⇧⌘E), Copy Path (⌥⌘C), Reload (⌘R), Delete (⌃X).

**The editor** is a palette screen: Folder (new snippets only, created at that folder's root), Name,
Keywords and Content. A new snippet starts with the clipboard's text when it is under 10,000
characters. ⌘↵ saves; Esc asks before discarding changes.

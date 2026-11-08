# Migrations

A migration repairs state that an older release left behind, such as a retired key in
`settings.json` or an orphaned default. It ships in exactly one stable release and is then deleted,
so the codebase never carries a history of its past formats.

## Invariants

- **Every migration lives in `Tinycast/Migrations/`**, one file and one `<Subject>Migration` type
  each. Its call sites name that type, so deleting the file fails the build at every one of them.
- **One release, then gone.** `Scripts/check-migrations.sh` fails `lint.sh` once a Lite release tag
  (`vX.Y.Z-lite.N`) contains the commit that added the file.
- **Missing it must be harmless.** A user who skips that release never runs it, so a migration only
  tidies. A value a later release depends on is never left to one.
- **Idempotent and silent.** It runs on every launch of its release, does nothing when there is
  nothing to repair, and reports nothing.
- **Every live migration has a row below.** The check fails for a file the table does not name.

## Adding one

Write the type in `Migrations/` and call it from `AppCore.start()` before anything reads the state it
repairs. Cover it with a harness of its own, so deleting it removes a whole file, one `run-tests.sh` entry and
one row in [testing.md](testing.md). Then add its row here.

## Deleting one

When the check fails, delete everything the row lists, then the row.

## Live migrations

| Migration | Repairs | Delete with it |
| --- | --- | --- |
| `CalendarRemovalMigration` | the `calendar` section left in `settings.json`, which the import reports as unknown on every launch, My Schedule in the compact bar, and the orphaned Calendar defaults, hotkeys and hidden-calendar list | its call in `AppCore.start()`, `Tests/calendar-removal-migration-test.swift`, its `run-tests.sh` entry and its testing.md row |
| `ThemesRemovalMigration` | the Raycast theme defaults (light and dark slots, imported themes, backdrop opacity) and the Theme command folder written into the extensions directory | its call in `AppCore.start()`, `Tests/themes-removal-migration-test.swift`, its `run-tests.sh` entry and its testing.md row |
| `EscapeKeyBehaviorRemovalMigration` | the retired Escape Key Behavior default and its `general.escapeKeyBehavior` key in `settings.json`, which the import would report as unknown | its call in `AppCore.start()`, `Tests/escape-key-behavior-removal-migration-test.swift`, its `run-tests.sh` entry and its testing.md row |

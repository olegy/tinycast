# Release

How a Tinycast Lite build reaches a Mac. The local development loop is in
[development.md](development.md); the signing identity is in [signing.md](signing.md).

There is no CI: every build is made and published from the release Mac, by two scripts that share
one Release build (`Scripts/lite-build.sh`, arm64, signed with the certificate in
`keys/signing.env`).

## Installing a local build

```sh
./Scripts/install.sh              # build Release, replace /Applications/Tinycast.app, launch it
./Scripts/install.sh --no-launch
```

Bump `TINYCAST_LITE_REVISION` in `project.yml` before installing new changes, so the installed copy
reports a version of its own.

## Version

`MARKETING_VERSION` is the upstream version Lite is based on plus a Lite revision:
`$(TINYCAST_UPSTREAM_VERSION)-lite.$(TINYCAST_LITE_REVISION)`, e.g. `0.12.1-lite.3`. That string is
the tag, the zip name and what the updater compares (`AppVersion`). The revision counts Lite's own
releases and never resets: moving to a new upstream base sets `TINYCAST_UPSTREAM_VERSION` and bumps
the revision like any other release (`0.12.1-lite.3` → `0.13.0-lite.4`).

## Publishing a release

1. Bump `TINYCAST_LITE_REVISION` in `project.yml`.
2. Add a `## <version>` section at the top of `CHANGELOG.md` — it becomes the release notes on
   GitHub and in the update window.
3. Commit and push `main`.
4. `./Scripts/release.sh` (`--no-upload` builds into `build/release/` only).

The script refuses a dirty tree, an unpushed `HEAD`, a version already tagged, a missing changelog
section and an ad-hoc build. It runs `Scripts/verify-signature.sh` and checks the build against
`BundleSignature.requirement` before anything is published, then creates the GitHub Release
`v<version>` on `ReleaseFeed.repository` with `Tinycast-<version>.zip`.

The zip is produced with `ditto -c -k --keepParent --sequesterRsrc` — the only zip that leaves the
code signature verifiable, which matters because the updater refuses any bundle whose signature does
not prove it is ours.

A release must keep three things true, or the updater skips it:

- **It carries a `.zip` asset.** A release without one is not installable and is not offered.
- **The tag parses as `vMAJOR.MINOR.PATCH-lite.N`** and is not marked prerelease.
- **It is not a draft.**

The builds are not notarized. A Mac that installs one by hand clears the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/Tinycast.app
```

Updates after that need nothing — see [features/updates.md](features/updates.md).

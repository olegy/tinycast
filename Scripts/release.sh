#!/bin/bash
# Publish a Tinycast Lite update: build Release, sign it with the certificate from
# keys/signing.env, and attach Tinycast-<version>.zip to a GitHub Release v<version>. Installed
# copies read the releases feed of `ReleaseFeed.repository` and update themselves.
#
# The builds are not notarized: a Mac that installs one by hand runs
#   xattr -dr com.apple.quarantine /Applications/Tinycast.app
# once; updates after that need nothing.
#
# Usage:
#   ./Scripts/release.sh               build and publish (tree clean, HEAD pushed, new version)
#   ./Scripts/release.sh --no-upload   build into build/release only
#
# Each release needs a new version (bump TINYCAST_LITE_REVISION in project.yml) and a
# `## <version>` section in CHANGELOG.md: it becomes the release notes on GitHub and in the update
# window.

set -euo pipefail
# shellcheck source=Scripts/lite-build.sh
. "$(dirname "$0")/lite-build.sh"
cd "$LITE_ROOT"

UPLOAD=true
for arg in "$@"; do
    case "$arg" in
        --no-upload) UPLOAD=false ;;
        --help | -h) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) lite_fail "unknown argument: $arg" ;;
    esac
done

REPO="$(sed -n 's/^ *static let repository = "\(.*\)"$/\1/p' Tinycast/Features/Updates/Model/ReleaseFeed.swift)"
[ -n "$REPO" ] || lite_fail "ReleaseFeed.repository not found"
if [ "$UPLOAD" = true ]; then
    command -v gh > /dev/null || lite_fail "gh is not installed (brew install gh)"
    [ -z "$(git status --porcelain)" ] || lite_fail "the working tree is not clean; every release must match a commit"
fi

lite_build
[ -n "$LITE_TEAM" ] || lite_fail "an ad-hoc build cannot be released; set TINYCAST_SIGN_IDENTITY in keys/signing.env"
VERSION="$(lite_version)"
TAG="v$VERSION"

# The version's CHANGELOG.md section: everything under `## <version>` up to the next `## `.
NOTES="$(awk -v heading="## $VERSION" '
    $0 == heading { found = 1; next }
    found && /^## / { exit }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"
[ -n "$NOTES" ] || lite_fail "CHANGELOG.md has no \"## $VERSION\" section; describe this release there first"

if [ "$UPLOAD" = true ]; then
    git fetch --quiet --tags origin
    git rev-parse -q --verify "refs/tags/$TAG" > /dev/null \
        && lite_fail "$TAG is already released; bump TINYCAST_LITE_REVISION in project.yml"
    COMMIT="$(git rev-parse HEAD)"
    git merge-base --is-ancestor "$COMMIT" origin/main \
        || lite_fail "HEAD is not on origin/main; push it before releasing"
fi

OUT="$LITE_ROOT/build/release"
mkdir -p "$OUT"
ZIP="$OUT/Tinycast-$VERSION.zip"
rm -f "$ZIP"
# The only zip that keeps the seal verifiable; plain `zip` drops symlinks and breaks it.
ditto -c -k --sequesterRsrc --keepParent "$LITE_APP" "$ZIP"
echo "Built $VERSION (team $LITE_TEAM): $ZIP"

if [ "$UPLOAD" = false ]; then
    echo "Not uploaded (--no-upload)."
    exit 0
fi

echo "Publishing $TAG to $REPO..."
gh release create "$TAG" "$ZIP" --repo "$REPO" --target "$COMMIT" \
    --title "Tinycast Lite $VERSION" --notes "$NOTES"
git fetch --quiet --tags origin
echo "Released $TAG. Installed copies offer it within a day, or at once from Check for Updates."

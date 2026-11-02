#!/bin/bash
# Sourced by install.sh and release.sh: the one Release build both ship, signed alike.
#
# The signing identity is named in the gitignored keys/signing.env:
#   TINYCAST_SIGN_IDENTITY="Apple Development: Name (CERTID)"
# Its Team ID must be the one `BundleSignature.requirement` pins, or installed copies refuse the
# update. Without the file the build is ad hoc: it runs, but never updates and loses Accessibility.

# shellcheck shell=bash

LITE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LITE_DERIVED="$LITE_ROOT/build/DerivedData"
LITE_APP="$LITE_DERIVED/Build/Products/Release/Tinycast.app"
LITE_BUNDLE_ID=com.olegy.tinycast

lite_fail() { echo "error: $*" >&2; exit 1; }

# The requirement the shipped updater checks, read from the source so the two never drift.
lite_requirement() {
    sed -n '/static let requirement = """/,/"""$/p' \
        "$LITE_ROOT/Tinycast/Features/Updates/Service/BundleSignature.swift" \
        | sed -e '1d' -e '$d' -e 's/^ *//' -e 's/ *\\$//' | tr '\n' ' ' | sed 's/ *$//'
}

# Sets LITE_IDENTITY and LITE_TEAM (empty for ad hoc).
lite_load_signing() {
    local env_file="$LITE_ROOT/keys/signing.env"
    # shellcheck disable=SC1090
    [ -f "$env_file" ] && . "$env_file"
    LITE_IDENTITY="${TINYCAST_SIGN_IDENTITY:--}"
    LITE_TEAM=""
    [ "$LITE_IDENTITY" = - ] && return 0
    # The Team ID is the certificate's OU; the parenthesised id in its name is the certificate's.
    LITE_TEAM="$(security find-certificate -c "$LITE_IDENTITY" -p 2> /dev/null \
        | openssl x509 -noout -subject -nameopt multiline 2> /dev/null \
        | sed -n 's/^ *organizationalUnitName *= *//p' | head -1)"
    [ -n "$LITE_TEAM" ] || lite_fail "no certificate \"$LITE_IDENTITY\" with a Team ID in the keychain"
}

lite_build() {
    command -v xcodegen > /dev/null || lite_fail "xcodegen is not installed (brew install xcodegen)"
    lite_load_signing
    (cd "$LITE_ROOT" && xcodegen generate > /dev/null)
    local signing=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$LITE_IDENTITY")
    [ -n "$LITE_TEAM" ] && signing+=(DEVELOPMENT_TEAM="$LITE_TEAM")
    echo "Building Tinycast (Release, arm64, ${LITE_TEAM:-ad hoc})..."
    mkdir -p "$LITE_ROOT/build"
    local log="$LITE_ROOT/build/lite-build.log"
    if ! xcodebuild -project "$LITE_ROOT/Tinycast.xcodeproj" -scheme Tinycast -configuration Release \
        -derivedDataPath "$LITE_DERIVED" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
        "${signing[@]}" OTHER_CODE_SIGN_FLAGS="--timestamp=none" build > "$log" 2>&1; then
        grep 'error:' "$log" | sort -u | head -40 >&2 || true
        lite_fail "build failed; full output: $log"
    fi
    [ -z "$LITE_TEAM" ] && return 0
    "$LITE_ROOT/Scripts/verify-signature.sh" "$LITE_APP" > /dev/null \
        || lite_fail "Scripts/verify-signature.sh rejected the build"
    codesign --verify --deep --strict -R="$(lite_requirement)" "$LITE_APP" \
        || lite_fail "the build does not satisfy BundleSignature.requirement"
}

lite_version() {
    /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$LITE_APP/Contents/Info.plist"
}

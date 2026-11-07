# Signing

Keeping the _same_ identity on every build is what makes macOS remember the Accessibility permission
across rebuilds and updates — ad-hoc signing changes every build and macOS forgets the grant. Lite
uses two:

- **Release** (`Scripts/install.sh`, `Scripts/release.sh`) signs with the **Apple Development**
  certificate of a free Personal Team, named in the gitignored `keys/signing.env`:

  ```sh
  TINYCAST_SIGN_IDENTITY="Apple Development: Name (CERTID)"
  ```

  Its Team ID (`SL2WXVL9K2`) is what `BundleSignature.requirement` pins, so it is what lets an
  installed copy accept an update. The Team ID is the certificate's `organizationalUnitName`; the
  parenthesised id in the identity's name is the certificate's own. Renewing the certificate keeps
  the team, so updates keep installing; macOS asks for Accessibility once more, because the
  designated requirement names the leaf.
- **Debug** (Xcode, `xcodebuild`) signs with the self-signed `Tinycast Self-Signed` identity that
  `project.yml` names, created once as below.

Get the Apple Development certificate in Xcode → Settings → Accounts → Manage Certificates → **+**.
Without `keys/signing.env` the scripts build ad hoc: the app runs, but never installs an update and
loses Accessibility on every rebuild, and `release.sh` refuses to publish it.

## 1. Create the `Tinycast Self-Signed` identity (once)

Run these in a terminal. They generate a self-signed code-signing certificate and import it into your
login keychain:

```sh
# Generate a self-signed code-signing cert (10-year, codeSigning use).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/tc-key.pem -out /tmp/tc-cert.pem \
  -subj "/CN=Tinycast Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12 (the non-empty password keeps `security import` happy).
openssl pkcs12 -export -inkey /tmp/tc-key.pem -in /tmp/tc-cert.pem \
  -name "Tinycast Self-Signed" -out /tmp/tc.p12 -passout pass:tinycast

# Import into the login keychain so codesign can use it without prompting.
security import /tmp/tc.p12 -k ~/Library/Keychains/login.keychain-db \
  -P tinycast -A -T /usr/bin/codesign

rm -f /tmp/tc-key.pem /tmp/tc-cert.pem /tmp/tc.p12
```

Verify it's there:

```sh
security find-identity -p codesigning | grep "Tinycast Self-Signed"
```

Now Debug builds (Xcode, VS Code F5, `xcodebuild`) sign with it, and you grant Accessibility once.

## Hardened runtime

**Release only**, on both targets: `ENABLE_HARDENED_RUNTIME: YES`. Debug
must stay without it — hardened runtime turns on library validation, and Xcode's
`Tinycast Dev.debug.dylib` is refused at launch because a self-signed identity carries no Team ID for
the loader to match. The flag is not part of the designated requirement, so turning it on costs no
Accessibility grant. Each entitlement in `Tinycast/Tinycast.entitlements` earns its place:

| Entitlement | Without it |
| --- | --- |
| `com.apple.security.cs.allow-jit` | JavaScriptCore cannot JIT, and every extension command runs on the interpreter |
| `com.apple.security.automation.apple-events` | Every Apple event is refused with `-1743` and no prompt — Get Info, the Finder selection an extension reads, and the System Events–driven system actions all die silently |
| `com.apple.security.device.camera` | The camera prompt never appears and access resolves as denied |
| `com.apple.security.personal-information.calendars` | An extension's Reminders request is denied in milliseconds with no dialog, and Tinycast never appears under System Settings › Reminders |

**A usage string is not enough under the hardened runtime.** `tccd` checks the matching entitlement
*before* it prompts, and without it logs "requires entitlement … but it is missing" and denies on the
spot — no dialog, no error, status still `.notDetermined`. A grant saved before the hardened runtime
arrived keeps working, since `tccd` does not re-check it, which is why this surfaces only on fresh
installs. Adding a protected resource therefore means adding its usage string *and* its entitlement.

`RESOURCE_ENTITLEMENTS` in `Scripts/verify-signature.sh` maps every protected resource's usage string
to its entitlement, including resources Tinycast does not use. That grants nothing — only
`Tinycast.entitlements` does, and a row whose usage string `Info.plist` doesn't declare is skipped. It
is there so a future feature that adds the usage string but forgets the entitlement fails the release
instead of shipping a prompt that can never appear.

Nothing else is needed: the only `dlopen` is Apple's own IOBluetooth, so library validation is left
on, and `node`, `ray` and shell commands are separate processes it never reaches. Bluetooth has no
hardened-runtime entitlement.

`./Scripts/verify-signature.sh <path-to-.app>` asserts all of this — the runtime flag on the app *and*
on `Contents/Helpers/ClipboardTextHelper`, an intact nested seal, no `get-task-allow`, and an
entitlement for every usage string `Info.plist` declares. `Scripts/lite-build.sh` runs it on every
signed build: a usage string missing its entitlement ships a permission that can never be granted.

## Quarantine (separate from signing)

macOS quarantines anything downloaded from the internet, and Gatekeeper blocks an app that is not
notarized. Lite releases are not, so a copy installed by hand is cleared once with
`xattr -dr com.apple.quarantine /Applications/Tinycast.app`; the updater's own downloads are never
quarantined.

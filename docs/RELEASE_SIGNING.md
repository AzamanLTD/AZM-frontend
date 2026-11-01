# Release signing

The upload key is environment-specific. It is **never** committed: `android/key.properties`
and every `*.jks` / `*.keystore` are ignored by `android/.gitignore`.

Release builds **require** the key. Without it Gradle stops with one sentence naming what is
missing, because a debug-signed bundle is refused by Play and a build that succeeds while
being unuploadable is worse than one that fails. Debug builds are unaffected and keep signing
with the debug key, so contributors and the integration lane never need the upload key.

## One-time: create the upload key

Run this from the repo root. It is the only copy of the key; lose it and Play App Signing
must be reset through Google support, so back it up somewhere durable and private.

```bash
keytool -genkeypair -v \
  -keystore android/upload-keystore.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -dname "CN=Azaman, O=Azaman, L=Accra, C=GH"
```

Then write `android/key.properties` (already gitignored):

```properties
storeFile=upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

`storeFile` is resolved relative to `android/`, so the plain filename above points at
`android/upload-keystore.jks`.

## CI secrets

Four repository secrets, exactly these names:

| secret | value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | the whole keystore file, base64-encoded as one string (`base64 -w0 android/upload-keystore.jks`) |
| `ANDROID_STORE_PASSWORD` | the keystore password, plain text |
| `ANDROID_KEY_ALIAS` | the key alias, plain text (`upload` in the command above) |
| `ANDROID_KEY_PASSWORD` | the key password, plain text |

Create the base64 value without newlines; `base64 -w0` writes it as a single line. On macOS
use `base64 -i android/upload-keystore.jks | tr -d '\n'`.

## How CI materialises the key

The `release-identity` job in `.github/workflows/android-integration.yml` writes both files
immediately before the build, from job-level environment variables bound to the secrets:

```yaml
- name: Materialise the upload key
  id: key
  run: |
    set -euo pipefail
    if [ -n "${KEYSTORE_BASE64:-}" ]; then
      echo "$KEYSTORE_BASE64" | base64 -d > android/upload-keystore.jks
      { echo "storeFile=upload-keystore.jks"; ... } > android/key.properties
      echo "real=true" >> "$GITHUB_OUTPUT"
    else
      # throwaway key so the signing wiring is still exercised
      ...
      echo "real=false" >> "$GITHUB_OUTPUT"
      echo "::warning::ANDROID_KEYSTORE_BASE64 is not set. ... NOT uploadable to Play."
    fi
```

Nothing is echoed: the step writes files and one flag. The keystore and `key.properties` are
deleted in an `if: always()` step, so a cached or self-hosted runner keeps no key material.

## How Gradle reads it

`android/app/build.gradle.kts` loads `android/key.properties` when it exists, builds a
`release` signing config from the four values, and points `buildTypes.release` at it. A
`gradle.taskGraph.whenReady` guard refuses any task whose name contains `Release` when the
file or any entry is missing, printing the missing entry names. That keeps the failure at the
one place it matters and leaves `flutter build apk --debug`, `flutter test` and the analyzer
untouched.

## The CI debug identity

The artifact the owner installs on a phone (`azaman-android-debug`) needs a signer whose
fingerprint can be registered in Firebase and stay valid. Hosted runners cannot provide that:
each runner generates its own debug keystore, so two independent runs of the same commit carry
two different certificates. Measured on this branch, two runs of `azaman-android-debug` produced
different signers, so the default is explicitly not treated as stable.

The separate CI debug identity fixes that. It is a different key from the upload key, it is used
only by the Android Integration debug build, and a developer's local debug signing is unchanged
(no `android/ci-debug.properties` on their machine means the ambient debug keystore is used).

| secret | value |
| --- | --- |
| `ANDROID_CI_DEBUG_KEYSTORE_BASE64` | the CI debug keystore file, base64-encoded as one line |
| `ANDROID_CI_DEBUG_STORE_PASSWORD` | its store password |
| `ANDROID_CI_DEBUG_KEY_ALIAS` | its key alias |
| `ANDROID_CI_DEBUG_KEY_PASSWORD` | its key password |

Generate it once, on your own machine. The file lives at **`android/ci-debug-keystore.jks`**, not
at the repository root: `android/.gitignore` carries `ci-debug-keystore.jks` and
`ci-debug.properties`, and those patterns are relative to `android/`. A keystore left at the root
would be committed by the next `git add -A`, so the commands below write it into `android/` and
`git check-ignore` confirms it before anything is staged.

Run from the repository root in PowerShell, using the JDK that ships with Android Studio (it is the
`keytool` you already have; a bare `keytool` may not be on `PATH`):

```powershell
# Android Studio's bundled JDK; adjust the drive if Studio is installed elsewhere.
$keytool = "${env:ProgramFiles}\Android\Android Studio\jbr\bin\keytool.exe"
if (-not (Test-Path $keytool)) { throw "keytool not found at $keytool" }

$storePass = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 20 | % {[char]$_})
$keyPass   = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 20 | % {[char]$_})

& $keytool -genkeypair -v `
  -keystore android\ci-debug-keystore.jks -storetype JKS `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias cidebug -storepass $storePass -keypass $keyPass `
  -dname "CN=Azaman CI Debug, O=Azaman, C=GH"

# It must be ignored before it can ever be committed.
git check-ignore -v android/ci-debug-keystore.jks
if ($LASTEXITCODE -ne 0) { throw "android/ci-debug-keystore.jks is NOT gitignored; stop" }

# The single-line secret value (no newlines).
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\ci-debug-keystore.jks")) | Set-Clipboard

# The fingerprints to register in Firebase for the Android app com.azaman.app.
& $keytool -list -v -keystore android\ci-debug-keystore.jks -alias cidebug -storepass $storePass
```

Paste that base64 string into `ANDROID_CI_DEBUG_KEYSTORE_BASE64`, and the two passwords and the
alias (`cidebug`) into the other three secrets. They are generated above rather than chosen, so
they are strong by construction; keep them with the file.

This key is **not** the upload key and must never be used to sign a release: `release` signing
reads `android/key.properties` only, `ciDebug` is applied to the debug build type only, and a
contract test enforces that separation.

Back the file up privately: the fingerprint is only stable while the same file is used. Then
register its SHA-1 and SHA-256 in Firebase for `com.azaman.app` and download a refreshed
`google-services.json` if the console issues one.

Until those four secrets exist, the debug job still produces `azaman-android-debug` with the same
name and retention, but its summary reports the signer as unstable and says not to register it.
Its APK is a layout and interaction artifact, not a verified Google Sign-In build. The prod-smoke
workflow uses the same identity and the same four secrets, reports its signer, and marks the
artifact unstable when they are absent.

## What the lane proves

`release-identity` builds the AAB and the release APK, then asserts with `aapt2` that the APK
package is `com.azaman.app`, reads the compiled bundle manifest to confirm the same package, and
verifies with `apksigner` and `keytool` that neither artifact is signed with a debug certificate
and that both carry the same certificate.
It also runs a release build with the key removed first and fails unless the build stops with
the expected message. When no upload key is configured the job still runs, but its summary labels
the result as diagnostic signing and states that the artifact is not uploadable and that its
throwaway certificate must not be registered in Firebase or Play Console. The artifact is `azaman-android-release`; the debug artifact
`azaman-android-debug` is unchanged.

```yaml
- name: Write upload key
  env:
    KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
    STORE_PASSWORD: ${{ secrets.ANDROID_STORE_PASSWORD }}
    KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
    KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
  run: |
    set -euo pipefail
    echo "$KEYSTORE_BASE64" | base64 -d > android/upload-keystore.jks
    cat > android/key.properties <<EOF
    storeFile=upload-keystore.jks
    storePassword=$STORE_PASSWORD
    keyAlias=$KEY_ALIAS
    keyPassword=$KEY_PASSWORD
    EOF
```

## Package ID

`applicationId` is `com.azaman.app` (the reverse of the product domain `azaman.app`).

Play treats the application ID as permanent from the first upload. Two things must match it
before a production build is attempted:

1. **Firebase**: register `com.azaman.app` as an Android app in the Firebase project and
   download the new `google-services.json`. `android-prod-smoke.yml` asserts that the
   supplied config names this package.
2. **Play Console**: the first release must be uploaded under `com.azaman.app`.

CI plants a placeholder `google-services.json` bound to `com.azaman.app` so the Gradle and
plugin integration is validated without the real secret.

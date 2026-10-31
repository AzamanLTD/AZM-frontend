# Firebase Android configuration — handoff

The Firebase Android configuration is environment-specific and is **never committed**.
`android/app/google-services.json` is produced locally or injected by CI. Nothing in this
document contains a real project identifier, key or credential.

## The package name to register

Register exactly this Android package in the Firebase project:

```
com.azaman.app
```

It must match `applicationId` in `android/app/build.gradle.kts`. That value is the Play
application ID, and Play treats it as permanent from the first upload, so it is the Firebase
registration that has to follow the build, not the other way round.

If a Firebase Android app already exists for the old `com.example.azaman`, leave it or delete
it, but the config used for release must contain a `client` whose
`client_info.android_client_info.package_name` is `com.azaman.app`. The android-prod-smoke
workflow asserts this and fails loudly otherwise.

## Certificate fingerprints to register

Authentication integrations that verify the calling app (Google Sign-In's Android client,
Phone Auth app verification, and Play Integrity / App Check when enabled) need the SHA-1 and
SHA-256 fingerprints of the certificates that actually sign the installed app. Register all
three that apply:

| certificate | where the fingerprint comes from | why it is needed |
| --- | --- | --- |
| Upload key (the keystore in `docs/RELEASE_SIGNING.md`) | `keytool -list -v -keystore android/upload-keystore.jks -alias upload` | builds you sign locally and CI-signed artifacts before Play re-signs them |
| Play App Signing certificate | Play Console → your app → Test and release → App integrity → App signing key certificate | the certificate on the build users actually install; without it Play-delivered builds fail verification |
| Local debug keystore | `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` | only for debug builds on your own machine |

The Play App Signing fingerprint only exists after the first upload, so the order is: register
the upload key fingerprint, upload the first bundle to Internal testing, then add the Play
signing fingerprint it shows you.

Read the values from the commands above; do not copy fingerprints from any other document.
Fingerprints are public material, but they are still yours to paste into the console.

## Where the file belongs

| context | path | how it gets there |
| --- | --- | --- |
| local machine | `android/app/google-services.json` | download from the Firebase console after registering the package; it is gitignored |
| CI | `android/app/google-services.json` written by the workflow | from the `GOOGLE_SERVICES_JSON` repository secret when set |
| release build | same path, same secret | the release job in `android-integration.yml` writes it before building |

`.gitignore` ignores `google-services.json`, so an accidental `git add -A` cannot publish it.
Verify with `git check-ignore -v android/app/google-services.json`.

## How CI gets it without committing secrets

Set a repository secret named `GOOGLE_SERVICES_JSON` whose value is the **entire file
contents**, exactly as downloaded. Both jobs in `android-integration.yml` write it to
`android/app/google-services.json` before the Gradle build:

```yaml
- name: Write Firebase configuration
  env:
    GOOGLE_SERVICES_JSON: ${{ secrets.GOOGLE_SERVICES_JSON }}
  run: |
    set -euo pipefail
    if [ -n "${GOOGLE_SERVICES_JSON:-}" ]; then
      printf '%s' "$GOOGLE_SERVICES_JSON" > android/app/google-services.json
    else
      # placeholder bound to com.azaman.app, plugin integration only
      ...
    fi
```

When the secret is absent the workflows still build, against a placeholder bound to
`com.azaman.app`. That validates Gradle and the Google Services plugin, and proves nothing
about Firebase itself: no project, no API key, no sign-in. A debug APK is evidence of layout
and interaction, never of OAuth or FCM.

## What stays owner-only

1. Creating or choosing the Firebase project, and registering `com.azaman.app` there.
2. Downloading the real `google-services.json` and adding it as the `GOOGLE_SERVICES_JSON`
   secret (or placing it locally).
3. Enabling the sign-in providers and adding the certificate fingerprints above.
4. Confirming, from a run of the integration lane with the secret set, that the config parsed
   against this package.

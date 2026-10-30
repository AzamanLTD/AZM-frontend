# Release signing

The upload key is environment-specific. It is **never** committed: `android/key.properties`
and every `*.jks` / `*.keystore` are ignored by `android/.gitignore`.

Without the key a release build still assembles, but Gradle prints a warning and signs with
the **debug** key. That APK/AAB cannot be uploaded to Play.

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

## CI

The workflows expect the same four values as repository secrets. Write them to
`android/key.properties` in a step before the build, for example:

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

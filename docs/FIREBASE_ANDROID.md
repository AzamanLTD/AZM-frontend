# Firebase Android configuration — handoff

The Firebase Android configuration is environment-specific and is **never committed**.
`android/app/google-services.json` is produced locally or injected by CI. Nothing in this
document contains a real project id, key, client id or credential.

## Project and package

| item | value |
| --- | --- |
| Firebase project | `azaman-app` (existing; the Admin credential was rotated, the project did not change) |
| Android package | `com.azaman.app` |
| Required OAuth entry | a Web client with `client_type: 3` |
| Web client id for the build | repository variable `GOOGLE_SERVER_CLIENT_ID` |

`com.azaman.app` must match `applicationId` in `android/app/build.gradle.kts`. Play treats the
application id as permanent from the first upload, so the Firebase registration follows the
build, and never the other way round. Do not create a second Firebase project for this build.

## One canonical secret

`GOOGLE_SERVICES_JSON` is the only Firebase secret. Its value is the **entire raw JSON** of
`google-services.json`, exactly as downloaded, and both workflows read it by that name:

| workflow | reads | writes |
| --- | --- | --- |
| `android-integration.yml` | `secrets.GOOGLE_SERVICES_JSON` | `android/app/google-services.json` |
| `android-prod-smoke.yml` | `secrets.GOOGLE_SERVICES_JSON` | `android/app/google-services.json` |

There is no second, separately encoded copy. Anything that reads a base64 variant is retired;
`test/ci/release_config_contract_test.dart` fails if either name comes back.

## What is validated, and what happens when it is wrong

Both workflows run `tool/ci/validate_google_services.py` before Gradle compiles. It reports
structural facts only, never the document or its keys:

- the file exists, is non-empty and is valid JSON;
- `project_info.project_id` is `azaman-app`;
- exactly one Android client carries `package_name: com.azaman.app` (other registered packages
  are tolerated, a second client for this package is not);
- the client object for `com.azaman.app` carries a Web OAuth client with `client_type: 3`;
- when `GOOGLE_SERVER_CLIENT_ID` is supplied, it is one of **that app's own** `client_type: 3`
  client ids, so the build cannot point at an audience that is not in the configuration.

The Web client check is scoped to our app on purpose. Firebase writes one client object per
registered Android app, and this project also registers the retired `com.example.azaman`. A Web
client attached only to that object is not a fallback: it issues tokens for that app, not for
ours, so supplying it fails with a message naming the app that owns it.

A supplied but wrong configuration **fails the run**. It is never replaced by the placeholder,
because a build that silently compiles against the wrong project looks healthy and signs nobody
in.

## Placeholder versus real

`android-integration.yml` keeps compiling when the secret is absent, using a placeholder bound
to `com.azaman.app`. That validates Gradle and the Google Services plugin and nothing else: no
project, no API key, no sign-in, no messaging.

The run says so. Its job summary prints `configuration = placeholder` and states that the build
is not connected to Firebase, that Google Sign-In and FCM are not verified by it, and that no
fingerprint should be registered from it. A successful APK build is never evidence that Google
authentication works.

`android-prod-smoke.yml` is the Firebase-connected device lane. It fails immediately when the
secret or the Web client id is missing, and never falls back to the placeholder.

## Certificates and fingerprints

Four different certificates are involved. They are not interchangeable, and registering the
wrong one is the most common cause of a silent sign-in failure on a real phone.

| certificate | what signs with it | where the fingerprint comes from | register in Firebase? |
| --- | --- | --- | --- |
| Local debug | a developer's own `flutter run` / local debug APK | `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` (macOS/Linux) or `%USERPROFILE%\.android\debug.keystore` on Windows | only if you test sign-in on that machine's debug build |
| CI debug | the `azaman-android-debug` artifact, once the dedicated identity is configured | printed by the `Report debug signer` step of the run that produced the APK | yes, after configuring it (see below) |
| Upload key | release APK and AAB built by CI or locally | printed by the release verification step, or `keytool -list -v -keystore android/upload-keystore.jks -alias upload` | yes |
| Play App Signing | the build users install from Play | Play Console → Test and release → App integrity | yes, after the first upload creates it |

Hosted runners do not have a stable debug certificate: the runner's debug keystore is generated
per machine, and two independent runs of the same commit produce two different certificates. A
fingerprint registered from one run would stop matching on the next. That is why the CI debug
identity exists (see `docs/RELEASE_SIGNING.md`); until it is configured, the artifact's signer is
reported in the summary as unstable and should not be registered.

## Which artifact is which

| artifact | workflow | purpose | uploadable to Play |
| --- | --- | --- | --- |
| `azaman-android-debug` | Android Integration | install on a physical phone for layout and interaction testing | no |
| `azaman-android-release` | Android Integration, `release-identity` job | the AAB and release APK, signed with the upload key | yes, when the upload key is configured; otherwise it is a diagnostic run with a throwaway key |
| `azaman-android-prod-debug` | Android Prod Smoke | Firebase-connected, production-backend debug APK for device smoke testing | no |

## Where the file belongs

| context | path | how it gets there |
| --- | --- | --- |
| local machine | `android/app/google-services.json` | downloaded from the Firebase console; gitignored |
| CI | `android/app/google-services.json` | written from `GOOGLE_SERVICES_JSON` before the build |

`.gitignore` ignores `google-services.json`; confirm with
`git check-ignore -v android/app/google-services.json`.

## What stays owner-only

1. Downloading the real `google-services.json` for `com.azaman.app` in `azaman-app`, and adding
   it as the `GOOGLE_SERVICES_JSON` secret.
2. Adding the repository variable `GOOGLE_SERVER_CLIENT_ID` with the `client_type: 3` Web client
   id. Never the Android client id, never a client secret.
3. Registering the fingerprints above (upload key, the dedicated CI debug certificate once it
   exists, and the Play App Signing certificate after the first upload).
4. Downloading a refreshed `google-services.json` after any further fingerprint registration,
   if the console changes it.

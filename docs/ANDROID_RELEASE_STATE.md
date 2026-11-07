# Android release state — verified 2026-11-07

Every line below was read from the repository or from a GitHub Actions run on
`main` at `0df35e7c15a22c37ac1ddfc785912da5512f0b4c`. Nothing here is copied
from an earlier handoff, and no secret value appears anywhere in it.

## Application identity

| Item | Value |
| --- | --- |
| `namespace` | `com.azaman.app` |
| `applicationId` | `com.azaman.app` |
| Kotlin package | `com.azaman.app` (`MainActivity`) |
| `minSdk` / `targetSdk` / `compileSdk` | Flutter defaults (24 / 36 / 36 at the pinned SDK) |

## Firebase and Google Sign-In

- The repository secret `GOOGLE_SERVICES_JSON` is present, and the run log
  records `supplied firebase: project_id=azaman-app android_clients=2
  package=com.azaman.app web_clients=1 web_clients_elsewhere=0
  server_client_id=matched`. The build compiled against the **real**
  configuration, not the placeholder.
- The repository variable `GOOGLE_SERVER_CLIENT_ID` is present and matched to a
  Web OAuth client (`client_type: 3`) attached to the `com.azaman.app` client
  object, which is the audience the backend token verification expects.
- The project also registers the retired `com.example.azaman`. The validator
  requires exactly one client for `com.azaman.app` and tolerates the retired
  entry; nothing in the build targets it.
- A wrong or partially valid configuration fails the run. It is never replaced
  by the placeholder.

**Google Sign-In has not been verified on a device.** CI proves the
configuration is valid and that the APK compiles against it; it cannot prove the
provider sheet returns a token. See the debug-signing caveat below.

## Release signing

Both jobs of Android Integration run
[41302266724](https://github.com/AzamanLTD/AZM-frontend/actions/runs/41302266724)
succeeded on `main`.

- The upload key secret material is present, and the `release-identity` job
  built and verified a real signed bundle: package `com.azaman.app`,
  AAB 122.1 MB, APK 150.6 MB.
- Verified certificate (from `apksigner`, normalised):

  | Field | Value |
  | --- | --- |
  | DN | `CN=Azaman, O=Azaman, L=Accra, C=GH` |
  | SHA-1 | `F2:E7:F5:B1:B2:B8:77:12:DA:9A:63:D2:2A:BB:91:F4:67:5B:0B:AA` |
  | SHA-256 | `D7:CB:D9:02:E2:F0:35:10:B9:56:B4:5D:F8:0D:20:B1:74:C5:9B:D3:9D:44:C5:E3:CB:7F:23:BF:4C:AF:6E:76` |

- Release signing never falls back to the debug key. The job first proves that a
  keyless release build fails with an explicit message, then materialises the
  upload key, then refuses to accept the artifact if `CN=Android Debug` appears.
- Because the artifact is signed by the expected upload identity, the
  `azaman-android-release` bundle is **upload-ready** in the signing sense. It is
  not yet published, and Play App Signing fingerprints are only known after the
  first upload.

## Debug signing and the device-testing artifact

| Item | Value |
| --- | --- |
| Artifact | `azaman-android-debug` (name and retention unchanged) |
| Latest size | 141,876,189 bytes |
| Expires | 2026-11-15 |
| Signer | the runner's throwaway debug certificate |

`ANDROID_CI_DEBUG_KEYSTORE_BASE64` is **not** configured, so every run signs the
debug APK with a freshly generated certificate. The workflow says so in its
summary and warns against registering the fingerprint. Consequences, stated
plainly:

- The debug artifact is fine for layout, navigation, the money lock, Bills
  surfaces, saved beneficiaries and notification flows.
- It cannot be used to prove Google Sign-In or FCM, because Firebase will not
  accept a certificate it has never seen, and the certificate changes run to
  run.
- Four secrets (`ANDROID_CI_DEBUG_KEYSTORE_BASE64`,
  `ANDROID_CI_DEBUG_STORE_PASSWORD`, `ANDROID_CI_DEBUG_KEY_ALIAS`,
  `ANDROID_CI_DEBUG_KEY_PASSWORD`) close this gap. Generation commands are in
  `docs/RELEASE_SIGNING.md`.

## Test lanes on `main`

`Flutter Quality` is configured for `pull_request`, `merge_group` and
`workflow_dispatch` only; it has no `push` trigger. The merge commit that is
current `main` therefore has Android Integration evidence but **no full-suite
Flutter Quality evidence from CI**. The full suite last ran in CI on
`190f7227d8` (2026-10-25).

This document was added in a pull request precisely so that the suite runs once
against a tree that is `main` plus documentation only; that run is the CI
evidence for the current code, not the older one.

## What remains owner-only

1. The four CI debug secrets, then register that certificate in Firebase for
   `com.azaman.app` and download a refreshed `google-services.json`.
2. Create the Play Console app under `com.azaman.app`, upload the first bundle,
   then register the Play App Signing fingerprints.
3. A device pass of Google Sign-In and FCM once step 1 is done.
4. KYC-at-financial-action depends on backend PR #383, which is still unmerged,
   so the gated withdrawal path cannot be exercised end to end.

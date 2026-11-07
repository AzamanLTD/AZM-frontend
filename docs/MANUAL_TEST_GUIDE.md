# Azaman — manual test guide

Test in order. Each step says what to look at, not just what to tap.

**Build under test:** branch `feat/member-money-lock-home-bills`. The APK is the
`azaman-android-debug` artifact from the Android Integration workflow.

Which artifact you are holding matters, and none of them is a release candidate:

| artifact | what it proves | what it does not |
| --- | --- | --- |
| `azaman-android-debug` | layout, interaction, navigation, the money lock, Bills surfaces, and a build compiled against the **real** Firebase configuration (project `azaman-app`, package `com.azaman.app`, matched Web OAuth client) | that Google Sign-In or FCM actually work. Both need a physical device and a certificate fingerprint registered in Firebase |
| `azaman-android-prod-debug` | the same, wired to the **production** backend, for a device dry run | nothing, unless the Firebase secret and Web client id are configured; and it is dispatch-only, never run without owner authorisation |
| `azaman-android-release` | the signed AAB **and** APK, built with the permanent upload key and verified against it | installability from Play, which needs the app registered there first |

The three things here are separate and easy to confuse:

1. **Configuration validity** — the Firebase document names the right project and
   package and the Web OAuth client belongs to `com.azaman.app`. CI checks this on
   every run, and the current runs use the real configuration, not the placeholder.
2. **Compilation** — the APK builds, carries `com.azaman.app`, and is signed by a
   certificate CI prints. CI checks this too.
3. **Device behaviour** — a human taps "Continue with Google" on a phone and sees a
   token come back, and a push notification arrives. **Nothing in CI can prove
   this.** It needs the APK's signing certificate registered in Firebase, plus a
   real device.

A green run therefore proves 1 and 2 only. Read the job summary before testing: it
states which Firebase configuration was used and which certificate signed the APK.
If the summary says the signer is unstable, a Google Sign-In test on that build is
expected to fail with a certificate mismatch, and that is a signing-registration
problem, not an app defect.

**What has been verified automatically** is listed at the end. Everything in
this guide is what CI cannot check.

---

Before you start, read [`ANDROID_RELEASE_STATE.md`](ANDROID_RELEASE_STATE.md):
it records which certificate signed the artifact in front of you and therefore
which of the items below you can actually complete today.

## 1. Cold start and the launch clip

Force-stop first (`Settings > Apps > Azaman > Force stop`). A warm start skips
this.

1. Tap the icon. The screen should be **black** with the silver mark — no white
   flash, no light grey ground, in both light and dark system themes.
2. The clip plays: mark swells, glass tile, then the wordmark is uncovered
   outward from its centre. About 3.8 s.
3. It ends on the wordmark and holds, then hands over.

**Pass:** one continuous piece of motion. The defect this replaces was "a logo
followed by separate images" — if the mark vanishes and a *different* lockup
appears, that is a failure, not a slow phone.

Also check:
- Background the app mid-clip and return. It must **not** replay.
- Enable **Remove animations** (Developer options). The clip should not run; you
  go straight to the settled wordmark and then onward.
- Watch specifically for a **duplicate mark**: one from the native splash, then
  a second appearing as the first video frame decodes. Any pause or cut at that
  seam is what this guide most wants to find.

## 2. First-launch tour (fresh install only)

Clear data to see it again: `Settings > Apps > Azaman > Storage > Clear data`.

- Three slides: wallet/balance, Shop-Stay-Eat-Ride, community/Susu.
- Slide 1 shows a card badged **Example balance**. No badge on a first-run
  screen would be a bug.
- Slide 2's four tiles read dark, blue, green, red — matching Marketplace.
- Slide 3 has no amounts and no "payment sent" style claims.
- **Skip** works from any slide and goes to login. **Get started** on the last
  slide also goes to login.
- The tour appears **before** login and must not appear again after you finish
  account setup.

Then, because the tour now follows your settings:
1. Finish login, go to Profile, change appearance to Light, and apply the Green
   card.
2. Clear app data and relaunch. The tour should now render **light with a green
   wallet card**.
3. Change to Dark and Red, clear data, relaunch: **dark with a red card**, and
   slide 2's category colours unchanged in both cases.

## 3. Returning sessions

- Launch a second time without clearing data: **no tour**, straight to the app
  (or login if signed out).
- If you are signed out but the tour was seen, you must not be shown the tour
  again; login is the destination.

## 4. Login providers

- **Apple** and **Google** open real system sheets. A button that does nothing,
  or an error with no explanation, is a failure worth recording exactly
  (provider, message).
- Cancel a sheet: you return to login with no error spam and no half-finished
  state.
- **Email** is the secondary route and sits on its own step with a back action.
- Wrong password and no-network cases must produce visible, actionable errors.

## 5. Account setup (authenticated, after registration)

This is the new single-step setup, and deliberately not a second tour.

- One screen: "Set up your account", four choices (P2P trading, Susu savings,
  Remittances, Business).
- **Continue** is disabled until you pick one. Pick one, continue, and you land
  on phone verification.
- **Decide later** also continues, and must not leave setup half-complete in a
  way the server disagrees with.
- There is **no deposit prompt, no KYC prompt and no permission dialog** here.
- Turn on airplane mode, tap Continue: you must stay on this screen and see
  "Could not save your setup. Check your connection." with a Retry. The app must
  not move forward and must not later behave as if setup was completed.
- The old claims are gone: nothing on this screen says "Ghana's Fastest P2P
  Platform", "Zero gas fees" or "no fraud, no chargebacks".

## 6. Phone verification, then optional permissions

- Enter your number, request a code. **A code is only real if the server issued
  one.** If you can proceed without a valid code, stop and report it: that is a
  security defect, not a UX one.
- Try a malformed number, an already-registered number, and a rapid second
  request (throttling): each needs a distinct, honest message.
- After the phone step, **contacts** is offered with a rationale first and a
  working "Not now". Denial and an empty address book must both be handled.
- **Location** is offered separately, also declinable, and only requests while
  the app is in the foreground.
- Neither permission may be a condition of using the app.

## 7. Appearance and card identity

- Wallet card press-and-hold opens the selector; swipe, Apply, and the app
  accent changes everywhere (nav, buttons, links).
- Light and dark both keep readable text on the accent, for all four variants.
- Marketplace categories stay fixed regardless of the applied card.

## 8. Known Play Store blockers (not testable in this build)

| Item | State |
|---|---|
| Package id | Settled: `com.azaman.app`, in `namespace`, `applicationId` and the Kotlin package. Registered in the existing Firebase project `azaman-app`. |
| Release signing | **Configured and verified.** The four `ANDROID_*` secrets exist, so `release-identity` builds with the permanent upload key and asserts the result. Measured signer of both artifacts: `CN=Azaman, O=Azaman, L=Accra, C=GH`, SHA-1 `F2:E7:F5:B1:B2:B8:77:12:DA:9A:63:D2:2A:BB:91:F4:67:5B:0B:AA`, SHA-256 `D7:CB:D9:02:E2:F0:35:10:B9:56:B4:5D:F8:0D:20:B1:74:C5:9B:D3:9D:44:C5:E3:CB:7F:23:BF:4C:AF:6E:76`. No keystore is in the repo. |
| CI debug signer | **Still unstable.** The dedicated CI debug identity is wired and ready, but its four `ANDROID_CI_DEBUG_*` secrets are not configured yet, so `azaman-android-debug` is signed by the runner's throwaway debug certificate and the certificate differs between runs. Do not register those fingerprints. Owner action: add the four secrets, then register the resulting fingerprint. |
| AAB | **Built by CI.** `release-identity` produces both `app-release.aab` and `app-release.apk` in the `azaman-android-release` artifact, with the same verified certificate. Uploading the first build to Play still needs the Play Console app to exist. |
| KYC at withdrawal | Client half present, backend gate unmerged, so the gate is inert here. Do not read a successful withdrawal as evidence it works. |

---

## Verified automatically, not by this guide

- Analyzer: 0 errors on `lib`.
- Public tour: showcase-free copy, Skip/Get started hand-off, local-only flag,
  320dp at 1.6x text without overflow, and six distinct captures in both
  appearances with a luminance check that the appearances differ.
- Wallet hero: renders the applied card variant (Blue, Green, Red, Dark), and
  the marketplace slide never consumes it.
- Account setup: single step; no retired claims or `1-3.webp` artwork; Continue
  gated on a choice; `POST /users/onboarding/complete` with the chosen use case;
  failure and dead-connection paths stay put with a retry and never claim
  completion; "Decide later" posts a null use case (the old Skip contract).
- Launch clip: contract tests for zero-start, mute, one-play-per-process,
  completion at the real end, and the failure path that holds the wordmark.

**Not verified anywhere yet:** the physical cold-start transition. No emulator
or device was available where this was built. Section 1 is the only place that
gets answered, and it needs your eyes.

## PIN setup and rotation require a confirmed server status

Azaman only offers PIN setup or rotation when the server tells the app whether
this account already has a PIN (`GET /security/app-unlock/capabilities`). That
route is part of the app-unlock contract, which is **not on backend `main` yet**
(backend PR #387 carries it, and is itself unmerged). Until it is deployed, the
Security Settings PIN card reads one of two states and neither of them is a form:

| what the card shows | what it means |
| --- | --- |
| "Checking your PIN status…" | the read is still in flight |
| "PIN status unavailable" + **Check again** | the server could not confirm the status |

In the unavailable state there is no PIN field and no save button, because the
two cases it cannot tell apart are "this account has no PIN" and "this account
has a PIN being replaced". Writing in that state would let a client overwrite a
PIN nobody proved, so nothing is sent to `/security/pin/set`.

**Do not read that state as a successful setup.** A tester who sees "PIN status
unavailable" has no PIN change, no PIN created, and no PIN removed. Tapping
**Check again** only re-asks the server.

When the capability read succeeds, the card is truthful in both directions:

- `pinConfigured: false` → a first-time form; the request carries `pin` only.
- `pinConfigured: true` → rotation; the request carries `pin` **and**
  `currentPin`, which the server verifies inside the same write.

If a change is refused, the screen reports the server's refusal and never
claims the PIN was changed. `PIN_ROTATION_CONFLICT` says the details changed
while the screen was open and that this attempt was not applied.

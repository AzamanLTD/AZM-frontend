# Azaman — manual test guide

Test in order. Each step says what to look at, not just what to tap.

**Build under test:** branch `feat/balance-card-identity`. The APK is the
`azaman-android-debug` artifact from the Android Integration workflow. It is
debug-signed: fine for internal testing, not a release candidate, and not
uploadable to Play.

**What has been verified automatically** is listed at the end. Everything in
this guide is what CI cannot check.

---

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
| Package id | Settled: `com.azaman.app`, in `namespace`, `applicationId` and the Kotlin package. Play treats it as permanent from the first upload. |
| Release signing | `release` uses the debug key; no keystore in the repo. Owner action. |
| AAB | CI builds a debug APK only, by design. First upload must be built locally. |
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

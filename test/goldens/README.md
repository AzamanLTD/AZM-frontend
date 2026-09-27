# Premium golden set — findings

Investigation record for the four `PremiumGlassContainer` golden tests that
fail on Linux CI while passing on a Windows dev box.

## Summary

Two independent, **measured** environmental causes. Neither is a product defect.

| # | Cause | Status | Fix |
|---|---|---|---|
| 1 | CI ran Flutter 3.47.0 / Dart 3.13.0; the project baseline is 3.47.5 / Dart 3.13.4 | **proven** | pin CI to `3.47.5` |
| 2 | The goldens were rasterised with **Roboto**, not the app's declared **Inter** | **proven** | load `Inter` explicitly in the harness |

## Measurements

Host drift on the same golden, before any fix (identical inputs, different host):

| Golden | Diff |
|---|---|
| `premium_glass_container_dark.png` | 0.76% (128px) |
| `premium_glass_container_v1_dark.png` | 0.75% (128px) |
| `premium_glass_container_light.png` | 0.60% (101px) |
| `premium_glass_container_v1_light.png` | 0.75% (128px) |

Font identity, measured on the SAME host (Windows) against the SAME committed
goldens:

| Theme font family | Diff vs committed golden |
|---|---|
| `ThemeData(...)` default → resolves to **Roboto** | 0.60–0.76% |
| `Inter` (bundled, explicitly loaded) | **17.6–18.0%** |

That 18% figure is the proof: switching the golden surface to the app's real
brand font moves the render a long way from the committed rasters. The
committed goldens were therefore generated **with the Roboto fallback**, not
with Inter.

A direct probe of the resolved theme confirms the family:

```
ThemeData(brightness: …, useMaterial3: true).textTheme.bodyMedium.fontFamily
  == Roboto
```

## Root cause 1 — Flutter version drift (proven)

`.github/workflows/flutter-ci.yml` pinned `flutter-version: '3.47.0'`, and the
failing run reported `Flutter 3.47.0 / Dart 3.13.0`. The project baseline
(`AZAMAN_PREMIUM_BUILD_BRIEF.md`) records `3.47.5 stable (rev 6a19cca564)`, and
local development runs `Flutter 3.47.5 / Dart 3.13.4`.

Golden rasters go through the engine's text and gradient code paths, so an
engine difference is a real rendering difference. `matchesGoldenFile`'s own
documentation warns that a golden rendered under a different Flutter version
may differ and need updating.

Fixed by pinning both workflows to `3.47.5`. This removes an uncontrolled
variable rather than tolerating it.

## Root cause 2 — the goldens never used the app font (proven)

`flutter_test` does not register the `pubspec.yaml` font bundle. A bare
`ThemeData(...)` resolves to the framework default — Roboto — so
`Text('Azaman')` in the golden surface was **never** rendered in Inter, despite
`pubspec.yaml` declaring it.

This matters beyond aesthetics: it means the goldens were validating a font the
product does not ship. The harness now loads the bundled face explicitly with
`FontLoader` (the pattern Flutter's `matchesGoldenFile` docs prescribe) and
names it in the theme.

Loading the font is real file I/O, so it must run inside
`tester.runAsync`; without that the test's fake-async zone never completes the
read and the suite hangs.

## Why the goldens must now be regenerated — deliberately

Fixing the font makes the suite *more* correct, and that necessarily changes the
committed rasters: the rasters must be re-rendered with Inter, which is an
~18% change by the measurement above.

That regeneration is a **deliberate, reviewable** act, not a green-build
shortcut, and the existing rule in `golden_harness.dart` is preserved
unchanged:

> Goldens are added or *deliberately* regenerated only. Never run
> `--update-goldens` to make a suite green — a regeneration must be a
> reviewable diff in the commit.

Regenerating on **one** host only would reintroduce cross-host drift, so the
regenerated rasters must be produced in the pinned CI environment (Linux,
Flutter 3.47.5) and committed from there. This is why the CI version pin is a
prerequisite and not an optional tidy-up.

## Gradient / dithering

The glass surface uses gradients and shadow layers, which are candidates for
renderer-dependent dithering. The 0.60–0.76% host-drift figures are small and
consistent with antialiasing plus gradient banding, but this was **not**
isolated: once the font is corrected the residual cannot be separated from the
font change until the Inter rasters exist. No production rendering behaviour
was modified to satisfy a test, and no test-only rendering toggle was
introduced.

## Remaining question

After regenerating with Inter on pinned Flutter 3.47.5, the suite should be
exact. If a sub-1% host drift remains, a tolerant comparator may be justified —
but only with: real pixel comparison, an explicit documented budget, failure on
structural differences, normal diff artifacts, no relative-path hacks, and
dedicated tests proving a real visual regression still fails. It must never be
a substitute for deterministic setup.

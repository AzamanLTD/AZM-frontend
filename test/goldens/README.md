# Premium golden set — findings

Investigation record for the four `PremiumGlassContainer` golden tests that
fail on Linux CI while passing on a Windows dev box.

## Summary

Two independent, **measured** environmental causes. Neither is a product defect.

| # | Cause | Status | Fix |
|---|---|---|---|
| 1 | CI ran Flutter 3.47.0 / Dart 3.13.0; the project baseline is 3.47.5 / Dart 3.13.4 | **proven** | pin CI to `3.47.5` |
| 2 | The goldens were rasterised with **Ahem** (flutter_test's built-in no-font fallback), so no real glyph was ever drawn | **proven** | load `Inter` explicitly in the harness, then regenerate |

Note: an earlier revision of this document attributed the old rasters to
Roboto. Visual inspection of the PNGs disproved that — see
"Regeneration — DONE" below.

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

## Regeneration — DONE, and CI is green

The four rasters were regenerated on Linux with Flutter 3.47.5 / Dart 3.13.4 via
a temporary, push-scoped, `contents: read` CI job that only rasterised and
uploaded an artifact. The four PNGs were then committed deliberately in
`f7f8dba`, and that temporary workflow was removed in `5b776b0`.

Linux CI on the final tree: **Analyze PASS, 599/599 tests PASS, zero golden
failures.**

### The old rasters were Ahem, not Roboto — corrected finding

Earlier revisions of this document reported that the committed rasters were
rendered in **Roboto**. Visual inspection of the actual PNGs disproved that:
the old rasters show **solid black boxes standing in for every glyph**, which is
Flutter's built-in **Ahem** test font — the font `flutter_test` uses when no real
face is loaded. Roboto was never involved.

So the precise sequence was:

1. The goldens were captured with **no real font loaded at all**, so `Ahem`
   substituted for every character.
2. The harness fix loads the real bundled **Inter** face, which is what made
   the ~18% difference appear.
3. The regenerated rasters are the first ones that actually show the product's
   typography.

This is a stronger version of the original finding, not a contradiction of it:
the committed baseline was not merely host-specific, it was not rendering real
text at all.

## Cross-host residual: 1.57–1.66%, and it is entirely text antialiasing

Windows (Flutter 3.47.5) against the Linux-generated committed rasters:

| Golden | Diff |
|---|---|
| `premium_glass_container_dark.png` | 1.66% |
| `premium_glass_container_v1_dark.png` | 1.64% |
| `premium_glass_container_light.png` | 1.57% |
| `premium_glass_container_v1_light.png` | 1.57% |

**What the diff artifacts show.** The `isolatedDiff` images for all four
goldens contain *only the glyphs of “Azaman”* — no geometry at all. The
`maskedDiff` images show the whole surface (rounded corners, rim, specular
streak, thickness line, two-layer shadow, gradient fill) as matching, with only
the text region lit up.

So the residual is **100% text antialiasing** on the glyph edges, from Skia's
rasteriser differing between the Windows and Linux hosts. Glass geometry does
not drift: no layout, rim, streak, corner or shadow difference is present.

**No comparator has been added.** A tolerance would have to cover 1.6% of a
small text-heavy raster while still failing on a real geometry regression, and
that trade is not free. The decision should be made deliberately with the
measurements above in hand, not inherited from a stale assumption.

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

# Testing Guide — AZM-frontend (for AI agents)

This repo does NOT ship a working Flutter/Dart toolchain in a fresh sandbox
clone. Every session that touches this repo starts from scratch. Follow this
exactly — skipping steps causes silent build failures or edits based on
stale/wrong file contents.

## 0. Before touching any file

```bash
cd /app/repos/AZM-frontend   # or wherever this repo is cloned
git fetch origin
git log HEAD..origin/main --oneline   # non-empty output = you are BEHIND
git pull origin main                  # fetch alone does NOT update the working tree
```

Never assume a previous session's uncommitted work survived — this sandbox
re-clones fresh on reset. Git history on `origin/main` is the only source of
truth. Do this at the start of every session and again right before your
final commit if the session ran long.

## 1. Toolchain requirements

- **Flutter 3.44.5+ / Dart 3.12+** (this pubspec needs `sdk: >=3.10.7`).
  Cached/bundled Flutter versions below this WILL fail to resolve deps.
- JDK 17 (`/app/jdk` in this sandbox) + Android SDK with `platform-35`,
  `build-tools;35.0.0`, NDK 28 (already provisioned in `/app/android-sdk`
  in this sandbox — verify with `ls /app/android-sdk` if unsure).
- Export before any flutter/gradle command:
  ```bash
  export PATH=/root/flutter/bin:/app/jdk/bin:$PATH
  export FLUTTER_ROOT=/root/flutter
  export ANDROID_HOME=/app/android-sdk
  ```

## 2. Static verification (cheap, do this for EVERY edit)

No Dart analyzer/LSP is reliably available in-sandbox for full type-checking,
so hand-verify before every commit:

```bash
# Brace/paren balance per touched file — mismatched counts = you broke something
python3 -c "
for f in ['path/to/file1.dart', 'path/to/file2.dart']:
    c = open(f).read()
    print(f'{f}: {{={c.count(chr(123))} }}={c.count(chr(125))} (={c.count(chr(40))} )={c.count(chr(41))}')"

# Dangling references — did you delete/rename something still used elsewhere?
grep -rn "OldClassName\|oldMethodName\|removed_field" lib/ --include="*.dart"

# Confirm anything you just added is exercised somewhere (not silently dead)
grep -rln "solveArc(" lib/  # example: check a function you removed a call to
                            # is (or isn't) still used before assuming it's dead
```

Also re-read the exact surrounding code with `sed -n 'START,ENDp' file.dart`
before editing — don't guess field names, constructor params, or which
constants a widget actually reads at runtime (this codebase has had real
bugs where a widget accepted a sizing parameter in its constructor but the
`build()` method silently used a hardcoded module-level constant instead —
grep for the constant name's actual usage, not just its declaration).

## 3. Run the test suite

```bash
flutter test test/widgets/liquid/liquid_widget_smoke_test.dart \
             test/widgets/liquid/liquid_placement_test.dart \
             test/widgets/liquid/liquid_engine_test.dart
```

Golden tests (`liquid_golden_test.dart`) compare pixel output against
`test/widgets/liquid/goldens/` — run separately, they're more prone to
false failures from font/DPI differences in the sandbox and are not required
before every commit, but run them if you touched painting/layout code:

```bash
flutter test test/widgets/liquid/liquid_golden_test.dart
```

There is no `flutter analyze` step wired into this guide on purpose — it's
slow and this repo's real bug history has been logic/wiring bugs (wrong
field used, wrong endpoint hit, stale response-shape assumption), not type
errors the analyzer would catch. Prioritize reading the actual code path
over trusting types.

## 4. Build a release APK to visually verify on-device

**Always build locally in the sandbox. GitHub Actions has stalled/failed for
APK builds on this repo before — do not use it.**

```bash
cd /app/repos/AZM-frontend
export PATH=/root/flutter/bin:/app/jdk/bin:$PATH
export FLUTTER_ROOT=/root/flutter
export ANDROID_HOME=/app/android-sdk

flutter clean && flutter pub get
flutter build apk --release --target-platform android-arm64
```

Takes ~5 minutes. Output: `build/app/outputs/flutter-apk/app-release.apk`.

**Known landmine:** if the build fails with
`package net.jonhanson.flutter_native_splash does not exist` (or any other
dev-only plugin), the stale `GeneratedPluginRegistrant.java` is referencing
a dev_dependency that Gradle never puts on the classpath for release builds.
Fix: comment out that package in `pubspec.yaml`'s `dev_dependencies` (and its
config block below `flutter:`) — the splash images it generates are
one-time-generated assets already committed, so the tool itself isn't
needed at build time — then `flutter pub get` again before rebuilding.

To ship the APK to the user: GitHub Releases, not chat file upload (`.apk`
files are blocked from direct chat upload as a platform security measure).

```bash
GH_TOKEN="<token>"; REPO="pyraxxz/AZM-frontend"
COMMIT_SHA=$(git rev-parse HEAD)

curl -s -X POST "https://api.github.com/repos/$REPO/releases" \
  -H "Authorization: token $GH_TOKEN" -H "Content-Type: application/json" \
  -d "{\"tag_name\":\"vX.Y.Z-demo\",\"target_commitish\":\"$COMMIT_SHA\",\"name\":\"...\",\"body\":\"...\",\"prerelease\":true}"
# grab the returned release "id", then:
curl -s -X POST "https://uploads.github.com/repos/$REPO/releases/<id>/assets?name=azaman-release.apk" \
  -H "Authorization: token $GH_TOKEN" -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary "@build/app/outputs/flutter-apk/app-release.apk"
```

## 5. Visual verification (the step most likely to be skipped — don't skip it)

Passing tests and a clean build do NOT mean a UI/animation change looks
right. This codebase has custom goo/liquid painters, radial layout solvers,
and spring animations where the only real verification is looking at it:

- If you have Browserbase/browser tooling available and the change is
  reachable from the Flutter **web** build, drive it and take screenshots
  before/after.
- Otherwise, build the APK (§4), and either install it yourself if you have
  device/emulator access, or hand the release link to the user with a short,
  specific description of exactly what to look at (which screen, which
  interaction, what changed) so they can confirm with a screenshot.
- If the user supplies a screenshot of a bug, read pixel positions/sizes
  literally — e.g. "satellites are the same size as the main pill" or
  "items overlap in a diagonal stack" are concrete, checkable claims against
  the actual widget code, not vibes. Go find the exact constant/function
  responsible before writing a fix.
- Never tell the user a visual bug is fixed without either seeing a
  render yourself or clearly stating you're relying on code-level
  reasoning because you couldn't render it this session.

## 6. Commit discipline

- Commit as the repo owner's identity (this repo pushes as `pyraxxz`, not
  as an agent identity) — check `git config user.name`/`user.email` if a
  fresh clone ever lacks it.
- Write commit messages that explain the *root cause*, not just the visible
  symptom — future sessions (including yourself, memory-less) will grep
  `git log` before re-diagnosing the same bug.
- One logical fix per commit where practical; push incrementally rather than
  batching unrelated changes, so a bad change is easy to `git revert`.

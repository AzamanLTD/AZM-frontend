# Testing & Build Guide — AZM-frontend (for AI agents)

This repo does NOT ship a working Flutter/Dart toolchain in a fresh sandbox
clone. Every session that touches this repo starts from scratch. Follow this
exactly — skipping steps causes silent build failures or edits based on
stale/wrong file contents.

---

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

---

## 1. Toolchain setup (required before any flutter command)

The sandbox has these pre-provisioned at known paths:

```bash
export PATH=/root/flutter/bin:/app/jdk/bin:$PATH
export FLUTTER_ROOT=/root/flutter
export ANDROID_HOME=/app/android-sdk
```

- **Flutter 3.47.0 / Dart 3.12+** — at `/root/flutter/bin`. Verify with
  `flutter --version`. If it reports <3.44.5, the pubspec (needs
  `sdk: >=3.10.7`) will fail to resolve deps.
- **JDK 17** — at `/app/jdk/bin`. Gradle 8.x (used by this project) requires
  JDK 17, not 11 or 21.
- **Android SDK** — at `/app/android-sdk`. Contains `platform-35`,
  `build-tools;35.0.0`, `ndk/28.0.x`, `cmdline-tools`. Verify with
  `ls /app/android-sdk`.
- **android/local.properties** — already configured in the repo with:
  ```
  sdk.dir=/app/android-sdk
  flutter.sdk=/root/flutter
  flutter.buildMode=release
  ```
  If missing or pointing elsewhere, regenerate it before building.

### google-services.json

The `android/app/google-services.json` must reference package name
`com.example.azaman`. If a fresh clone has a different one (or it's missing),
the Gradle build will fail at the `:app:processReleaseGoogleServices` task.
The correct file is committed in the repo — `git checkout
android/app/google-services.json` to restore it if a prior session modified
it.

---

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
constants a widget actually reads at runtime. This codebase has had real
bugs where a widget accepted a sizing parameter in its constructor but the
`build()` method silently used a hardcoded module-level constant instead.
Grep for the constant name's actual usage, not just its declaration.

---

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

---

## 4. Build a release APK

**Always build locally in the sandbox. Never use GitHub Actions — it has
stalled and failed repeatedly for APK builds on this repo.**

### 4a. Resolve dependencies

```bash
cd /app/repos/AZM-frontend
export PATH=/root/flutter/bin:/app/jdk/bin:$PATH
export FLUTTER_ROOT=/root/flutter
export ANDROID_HOME=/app/android-sdk

flutter pub get
```

### 4b. Known landmine: flutter_native_splash

If the build fails with `package net.jonhanson.flutter_native_splash does
not exist` or `GeneratedPluginRegistrant.java:XX: error: cannot find
symbol`, the stale `GeneratedPluginRegistrant.java` is referencing
`flutter_native_splash` — a **dev-only** plugin that Gradle never puts on
the release classpath.

Fix: comment out the `flutter_native_splash` entry in `pubspec.yaml`'s
`dev_dependencies:` section AND its config block under `flutter:`:

```yaml
# Before (broken):
dev_dependencies:
  flutter_native_splash: ^x.x.x

flutter:
  flutter_native_splash:
    color: "#FFFFFF"
    image: "assets/images/azaman_logo_splash.png"
  android_12:
    image: "assets/images/azaman_logo_splash.png"
    color: "#FFFFFF"

# After (works):
dev_dependencies:
  # flutter_native_splash: ^x.x.x   # removed — splash images already generated

flutter:
  # flutter_native_splash:           # commented out — not needed at build time
  #   color: "#FFFFFF"
  #   image: "assets/images/azaman_logo_splash.png"
  #   android_12:
  #     image: "assets/images/azaman_logo_splash.png"
  #     color: "#FFFFFF"
```

The splash screen images it generates are one-time-generated PNG assets
already committed in `android/app/src/main/res/` — the tool itself isn't
needed at build time. After commenting it out, run `flutter pub get` again
to regenerate `GeneratedPluginRegistrant.java` without the plugin, then
rebuild.

To verify the fix worked:
```bash
grep -c "flutter_native_splash" android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
# Should print: 0
```

### 4c. Build the APK

```bash
flutter build apk --release --target-platform android-arm64
```

Takes ~5 minutes. Output:
`build/app/outputs/flutter-apk/app-release.apk` (~88-92MB).

Use `--target-platform android-arm64` for a smaller, faster build. If you
need a fat APK for legacy device support, omit the flag (builds all ABIs,
~2x larger, ~2x slower).

### 4d. If the build hangs or crashes with memory errors

The Gradle daemon can OOM on sandbox instances with limited RAM. Workaround:

```bash
# Kill any stale Gradle daemons first
pkill -f gradle || true
pkill -f dart || true

# Build with reduced memory + no daemon
flutter build apk --release --target-platform android-arm64 \
  --no-defer-components
```

If it still hangs, run in a **tmux session** instead of blocking bash so
you can monitor it without timeout risk:

```bash
# In a tmux session:
cd /app/repos/AZM-frontend
export PATH=/root/flutter/bin:/app/jdk/bin:$PATH
export FLUTTER_ROOT=/root/flutter
export ANDROID_HOME=/app/android-sdk
flutter build apk --release --target-platform android-arm64 2>&1 | tee /tmp/apk-build.log
```

Then check progress with `tail -20 /tmp/apk-build.log` every 60-90 seconds.

---

## 5. Publish the APK to a GitHub Release

`.apk` files are **blocked from direct chat upload** (security policy —
flagged as dangerous by virus scanners). The delivery path is GitHub
Releases.

### 5a. Extract the GitHub token

The repo remote URL contains the token (it was cloned with it):

```bash
cd /app/repos/AZM-frontend
GH_TOKEN=$(git remote get-url origin | sed -n 's/.*:\/\/x-access-token:\(.*\)@.*/\1/p')
REPO="pyraxxz/AZM-frontend"
COMMIT_SHA=$(git rev-parse HEAD)
```

### 5b. Create the release

```bash
RESPONSE=$(curl -s -X POST "https://api.github.com/repos/$REPO/releases" \
  -H "Authorization: token $GH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"tag_name\": \"vX.Y.Z-demo\",
    \"target_commitish\": \"$COMMIT_SHA\",
    \"name\": \"vX.Y.Z-demo — short description\",
    \"body\": \"## What's new\n\n- bullet point 1\n- bullet point 2\n\n## APK\n\nDownload the APK below, install on an arm64 device.\",
    \"prerelease\": true
  }")

# Extract the release ID for the asset upload
RELEASE_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id','FAILED'))")
echo "Release ID: $RELEASE_ID"
```

### 5c. Upload the APK as a release asset

```bash
curl -s -X POST \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=azaman-release.apk" \
  -H "Authorization: token $GH_TOKEN" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary "@build/app/outputs/flutter-apk/app-release.apk" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Download: {d.get(\"browser_download_url\", d)}')"
```

### 5d. Versioning convention

Use `vX.Y.Z-demo` tags (e.g. `v1.0.7-demo`). The `-demo` suffix marks these
as pre-release/demo builds — they show up under "Releases" on GitHub but
are clearly not production GA. Bump the patch number for each new build.

The user accesses the APK directly at:
```
https://github.com/pyraxxz/AZM-frontend/releases/download/vX.Y.Z-demo/azaman-release.apk
```

---

## 6. Visual verification (the step most likely to be skipped — don't skip it)

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

---

## 7. Commit discipline

- Commit as the repo owner's identity (this repo pushes as `pyraxxz`, not
  as an agent identity) — check `git config user.name`/`user.email` if a
  fresh clone ever lacks it.
- Write commit messages that explain the *root cause*, not just the visible
  symptom — future sessions (including yourself, memory-less) will grep
  `git log` before re-diagnosing the same bug.
- One logical fix per commit where practical; push incrementally rather than
  batching unrelated changes, so a bad change is easy to `git revert`.

---

## 8. Quick reference — full build + release script

Run this end-to-end (assumes you're at the repo root with the exports set):

```bash
#!/bin/bash
set -e
export PATH=/root/flutter/bin:/app/jdk/bin:$PATH
export FLUTTER_ROOT=/root/flutter
export ANDROID_HOME=/app/android-sdk

# 1. Pull latest
git fetch origin && git pull origin main

# 2. Resolve deps
flutter pub get

# 3. Build APK (~5 min)
flutter build apk --release --target-platform android-arm64

# 4. Extract GitHub token from remote
GH_TOKEN=$(git remote get-url origin | sed -n 's/.*:\/\/x-access-token:\(.*\)@.*/\1/p')
REPO="pyraxxz/AZM-frontend"
COMMIT_SHA=$(git rev-parse HEAD)

# 5. Create release
RESPONSE=$(curl -s -X POST "https://api.github.com/repos/$REPO/releases" \
  -H "Authorization: token $GH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"tag_name\":\"v1.0.8-demo\",\"target_commitish\":\"$COMMIT_SHA\",\"name\":\"v1.0.8-demo\",\"body\":\"Latest demo build\",\"prerelease\":true}")

RELEASE_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# 6. Upload APK
curl -s -X POST \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=azaman-release.apk" \
  -H "Authorization: token $GH_TOKEN" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary "@build/app/outputs/flutter-apk/app-release.apk" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'✓ {d[\"browser_download_url\"]}')"
```

This entire script takes ~6 minutes and produces a downloadable APK on the
GitHub releases page.

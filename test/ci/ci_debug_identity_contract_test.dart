// CONTRACTS FOR THE CI DEBUG SIGNING IDENTITY.
//
// The names are the whole contract: a repository secret added under a
// different name is silently absent, the build quietly falls back to the
// runner's throwaway debug certificate, and nothing fails. A path-shaped name
// such as ANDROID_CI_DEBUG_STORE_FILE would behave exactly that way, which is
// why it is asserted against here rather than trusted.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _integration = '.github/workflows/android-integration.yml';
const _prodSmoke = '.github/workflows/android-prod-smoke.yml';
const _gradle = 'android/app/build.gradle.kts';
const _guide = 'docs/RELEASE_SIGNING.md';

const _names = [
  'ANDROID_CI_DEBUG_KEYSTORE_BASE64',
  'ANDROID_CI_DEBUG_STORE_PASSWORD',
  'ANDROID_CI_DEBUG_KEY_ALIAS',
  'ANDROID_CI_DEBUG_KEY_PASSWORD',
];

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing; the CI debug identity contract cannot hold');
  }
  return file.readAsStringSync();
}

void main() {
  test('both workflows read all four secrets, under the same names', () {
    for (final workflow in [_integration, _prodSmoke]) {
      final yaml = _read(workflow);
      for (final name in _names) {
        expect(
          yaml,
          contains('secrets.$name'),
          reason: '$workflow must read $name',
        );
      }
    }
  });

  test('the signing guide documents exactly those four', () {
    final doc = _read(_guide);
    for (final name in _names) {
      expect(doc, contains(name), reason: 'undocumented secret: $name');
    }
    expect(
      doc,
      isNot(contains('ANDROID_CI_DEBUG_STORE_FILE')),
      reason: 'a path-shaped name is never read, so the key would be absent',
    );
  });

  test('the keystore is documented under android/ and stays ignored', () {
    final doc = _read(_guide);
    expect(doc, contains(r'android\ci-debug-keystore.jks'));
    expect(doc, contains('git check-ignore -v android/ci-debug-keystore.jks'));
    expect(
      _read('android/.gitignore'),
      contains('ci-debug-keystore.jks'),
      reason: 'the file must be ignored before it can be committed',
    );
  });

  test('the debug build can only ever take the debug identity', () {
    final gradle = _read(_gradle);
    final debugBlock = gradle.substring(
      gradle.indexOf('debug {'),
      gradle.indexOf('release {'),
    );
    expect(debugBlock, contains('signingConfigs.getByName("ciDebug")'));
    expect(
      debugBlock,
      isNot(contains('"release"')),
      reason: 'the upload key must never sign a debug artifact',
    );
  });
}

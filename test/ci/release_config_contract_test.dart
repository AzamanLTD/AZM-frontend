// Contracts for the Android release configuration itself.
//
// These are not widget tests: they read the workflow files, the Gradle script
// and the shared validator as text and assert the properties that a physical
// phone install and a Play upload actually depend on. Every one of them came
// from a defect that had already reached a branch, so they are written to fail
// when the property is lost, not when a line moves.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _integration = '.github/workflows/android-integration.yml';
const _prodSmoke = '.github/workflows/android-prod-smoke.yml';
const _gradle = 'android/app/build.gradle.kts';
const _validator = 'tool/ci/validate_google_services.py';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path is missing; the release configuration contract cannot hold');
  }
  return file.readAsStringSync();
}

/// Joins shell line continuations so a command split across lines is read as
/// the one command the shell will run.
List<String> _commands(String yaml) {
  final lines = yaml.split('\n');
  final out = <String>[];
  var buffer = '';
  for (final line in lines) {
    if (buffer.isEmpty) {
      if (!line.contains('flutter build')) continue;
      buffer = line;
    } else {
      buffer = '$buffer ${line.trim()}';
    }
    if (buffer.trimRight().endsWith(r'\')) {
      buffer = buffer.trimRight().substring(0, buffer.trimRight().length - 1);
      continue;
    }
    out.add(buffer.trim());
    buffer = '';
  }
  return out;
}

bool _hasPython() {
  try {
    final probe = Process.runSync('python3', ['--version']);
    return probe.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('one canonical Firebase secret', () {
    test('both workflows read the raw JSON secret under one name', () {
      for (final workflow in [_integration, _prodSmoke]) {
        expect(
          _read(workflow),
          contains(r'secrets.GOOGLE_SERVICES_JSON'),
          reason: '$workflow must read the canonical secret',
        );
      }
    });

    test('the duplicated base64 contract is gone from workflows and docs', () {
      final sources = <String>[
        _integration,
        _prodSmoke,
        'docs/FIREBASE_ANDROID.md',
        'docs/RELEASE_SIGNING.md',
        'docs/MANUAL_TEST_GUIDE.md',
      ];
      for (final source in sources) {
        final text = _read(source);
        expect(
          text,
          isNot(contains('AZM_ANDROID_GOOGLE_SERVICES_JSON_B64')),
          reason: '$source still names the retired base64 secret',
        );
        expect(
          text,
          isNot(contains('GOOGLE_SERVICES_JSON_B64')),
          reason: '$source still carries a second, encoded variable',
        );
      }
    });

    test('both workflows write the configuration to the app module', () {
      for (final workflow in [_integration, _prodSmoke]) {
        expect(
          _read(workflow),
          contains('android/app/google-services.json'),
          reason:
              '$workflow must write the file the Google Services plugin reads',
        );
      }
    });
  });

  group('the Web OAuth client id reaches every build', () {
    test('every flutter build passes the dart-define', () {
      for (final workflow in [_integration, _prodSmoke]) {
        final commands = _commands(_read(workflow));
        expect(
          commands,
          isNotEmpty,
          reason: '$workflow should contain at least one build command',
        );
        for (final command in commands) {
          // The keyless-release probe is deliberately bare: it must fail.
          if (command.contains('nokey')) continue;
          expect(
            command,
            contains('--dart-define=GOOGLE_SERVER_CLIENT_ID'),
            reason:
                'a build command in $workflow omits the Web client id: $command',
          );
        }
      }
    });

    test(
      'the debug APK, release APK, bundle and smoke APK are all covered',
      () {
        final integration = _commands(_read(_integration));
        final smoke = _commands(_read(_prodSmoke));
        expect(
          integration.any((c) => c.contains('flutter build apk --debug')),
          isTrue,
          reason: 'the Android Integration debug APK must pass the client id',
        );
        expect(
          integration.any((c) => c.contains('appbundle --release')),
          isTrue,
          reason: 'the release bundle must pass the client id',
        );
        expect(
          integration.any(
            (c) => c.contains('apk --release') && !c.contains('nokey'),
          ),
          isTrue,
          reason: 'the release APK must pass the client id',
        );
        expect(
          smoke.any((c) => c.contains('flutter build apk')),
          isTrue,
          reason: 'the smoke APK must pass the client id',
        );
      },
    );
  });

  group('Workfront artifact contract', () {
    test('the debug artifact keeps its exact name and retention', () {
      final yaml = _read(_integration);
      expect(yaml, contains('name: azaman-android-debug'));
      expect(yaml, contains('retention-days: 14'));
      expect(
        yaml,
        isNot(contains('name: azaman-android-debug-')),
        reason: 'the physical-device artifact must not be renamed or suffixed',
      );
    });

    test('the release artifact is separate from the debug artifact', () {
      final yaml = _read(_integration);
      expect(yaml, contains('name: azaman-android-release'));
      expect(yaml, isNot(contains('name: azaman-android-release-debug')));
    });
  });

  group('Firebase builds are labelled honestly', () {
    test('the placeholder path says sign-in and FCM are not verified', () {
      final yaml = _read(_integration);
      expect(yaml, contains('not connected to Firebase'));
      expect(yaml, contains('Google Sign-In and FCM are'));
      expect(
        yaml,
        contains('mode=placeholder'),
        reason: 'the run must record which configuration it used',
      );
    });

    test('a supplied configuration is validated, never replaced', () {
      final yaml = _read(_integration);
      expect(yaml, contains('--project azaman-app'));
      expect(yaml, contains('--package com.azaman.app'));
      expect(
        yaml,
        contains('--server-client-id'),
        reason: 'the OAuth audience must be checked against the configuration',
      );
      // The validate call sits on the supplied branch, before the placeholder.
      final supplied = yaml.indexOf('printf \'%s\' "\$GOOGLE_SERVICES_JSON"');
      final validator = yaml.indexOf('validate_google_services.py');
      expect(supplied, greaterThan(0));
      expect(validator, greaterThan(supplied));
    });

    test(
      'prod smoke fails early without the configuration or the client id',
      () {
        final yaml = _read(_prodSmoke);
        expect(
          yaml,
          contains('Required secret GOOGLE_SERVICES_JSON is missing'),
        );
        expect(
          yaml,
          contains('Required variable GOOGLE_SERVER_CLIENT_ID is missing'),
        );
        expect(
          yaml,
          isNot(contains('azaman-ci.appspot.com')),
          reason: 'prod smoke must never fall back to the CI placeholder',
        );
      },
    );
  });

  group('release signing stays fail-closed', () {
    test('release reads the upload key and never the debug key', () {
      final gradle = _read(_gradle);
      expect(gradle, contains('signingConfigs.getByName("release")'));
      final releaseBlock = gradle.substring(
        gradle.indexOf('buildTypes {'),
        gradle.indexOf('gradle.taskGraph.whenReady'),
      );
      expect(
        releaseBlock,
        isNot(contains('signingConfigs.getByName("debug")')),
        reason: 'a release build must never silently use the debug key',
      );
      expect(gradle, contains('Release builds are signed with the upload key'));
    });

    test('the CI debug identity is separate from the release identity', () {
      final gradle = _read(_gradle);
      expect(gradle, contains('create("ciDebug")'));
      final debugBlock = gradle.substring(
        gradle.indexOf('debug {'),
        gradle.indexOf('release {'),
      );
      expect(debugBlock, contains('signingConfigs.getByName("ciDebug")'));
      expect(
        _read('android/.gitignore'),
        contains('ci-debug-keystore.jks'),
        reason: 'the CI debug key material must be ignored like the upload key',
      );
    });

    test('the debug job reports its signer and cleans up key material', () {
      final yaml = _read(_integration);
      expect(yaml, contains('- name: Report debug signer'));
      expect(yaml, contains('apksigner'));
      expect(yaml, contains('Remove CI debug key material'));
      expect(yaml, contains('if: always()'));
    });
  });

  group('the shared validator', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('fbcfg'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String write(String name, Object? data) {
      final file = File('${tmp.path}/$name');
      file.writeAsStringSync(data is String ? data : _json(data));
      return file.path;
    }

    ProcessResult run(String path, {String? project, String? clientId}) {
      return Process.runSync('python3', [
        _validator,
        '--file',
        path,
        if (project != null) ...['--project', project],
        if (clientId != null) ...['--server-client-id', clientId],
      ]);
    }

    test('accepts the expected production shape', () {
      final path = write('ok.json', _config());
      final result = run(
        path,
        project: 'azaman-app',
        clientId: 'web-1.apps.googleusercontent.com',
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('project_id=azaman-app'));
      expect(
        result.stdout,
        contains('server_client_id=matched'),
        reason: 'the validator must confirm the audience it was given',
      );
    });

    test('rejects the wrong project', () {
      final path = write(
        'wrong-project.json',
        _config(project: 'other-project'),
      );
      final result = run(path, project: 'azaman-app');
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('expected'));
    });

    test('rejects a config without the Android package', () {
      final path = write(
        'wrong-package.json',
        _config(package: 'com.example.other'),
      );
      final result = run(path, project: 'azaman-app');
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('no Android client for'));
    });

    test('rejects a config with no Web OAuth client', () {
      final path = write('no-web.json', _config(webClient: false));
      final result = run(path, project: 'azaman-app');
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('client_type 3'));
    });

    test('rejects a client id that is not in the configuration', () {
      final path = write('mismatch.json', _config());
      final result = run(
        path,
        project: 'azaman-app',
        clientId: 'someone-else.apps.googleusercontent.com',
      );
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('not one of the'));
    });

    test('rejects malformed JSON', () {
      final path = write('broken.json', '{"project_info": ');
      final result = run(path);
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('not valid JSON'));
    });

    test('rejects a missing file', () {
      final result = run('${tmp.path}/absent.json');
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('missing or empty'));
    });

    test('validates the placeholder by structure and package only', () {
      final path = write(
        'placeholder.json',
        _config(project: 'azaman-ci', webClient: false),
      );
      final result = run(path);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('project_id=azaman-ci'));
    });

    test('never prints key material', () {
      final path = write('ok.json', _config());
      final result = run(path, project: 'azaman-app');
      expect(result.stdout, isNot(contains('AIza')));
      expect(result.stdout, isNot(contains('api_key')));
    });
  }, skip: _hasPython() ? false : 'python3 is unavailable in this environment');

  group('the validator is wired into every workflow that compiles', () {
    test('both workflows call the shared script', () {
      for (final workflow in [_integration, _prodSmoke]) {
        expect(
          _read(workflow),
          contains('tool/ci/validate_google_services.py'),
          reason: '$workflow must validate rather than trust the configuration',
        );
      }
    });
  });
}

String _json(Object? data) => const JsonEncoderShim().convert(data);

class JsonEncoderShim {
  const JsonEncoderShim();
  String convert(Object? value) => _encode(value);

  static String _encode(Object? v) {
    if (v is Map) {
      final entries = v.entries
          .map((e) => '"${e.key}":${_encode(e.value)}')
          .join(',');
      return '{$entries}';
    }
    if (v is List) return '[${v.map(_encode).join(',')}]';
    if (v is String) return '"$v"';
    if (v is num || v is bool) return '$v';
    if (v == null) return 'null';
    throw ArgumentError('unsupported $v');
  }
}

Map<String, Object?> _config({
  String project = 'azaman-app',
  String package = 'com.azaman.app',
  bool webClient = true,
}) {
  return {
    'project_info': {
      'project_number': '123456789012',
      'project_id': project,
      'storage_bucket': '$project.appspot.com',
    },
    'client': [
      {
        'client_info': {
          'mobilesdk_app_id': '1:123456789012:android:abcdef1234567890',
          'android_client_info': {'package_name': package},
        },
        'oauth_client': [
          if (webClient)
            {'client_id': 'web-1.apps.googleusercontent.com', 'client_type': 3},
        ],
        'api_key': [
          {'current_key': 'AIzaFAKEKEYFORCONTRACTTESTONLY0000000000'},
        ],
      },
    ],
    'configuration_version': '1',
  };
}

// =============================================================================
// FRAMEWORK ERROR CHAIN — Sentry interplay (defect audit 2026-10-28)
//
// The defect report asked whether the custom `FlutterError.onError` in
// main.dart interferes with the configured Sentry error-reporting path.
// It DID: when SENTRY_DSN is compiled in, SentryFlutter.init installs its
// own FlutterError.onError (capture + present). _bootstrap then REPLACED
// it with a handler that only debugPrints — framework errors were never
// reported to Sentry. The fix chains onto the installed handler instead
// of clobbering it (installAzamanFrameworkErrorHooks).
//
// This test verifies the CHAIN BEHAVIOR — one invocation routes to BOTH
// the previously-installed handler (Sentry's in production) and the
// app's local error record. No Sentry SDK needed: the chained handler is
// a recording stub, proving the dispatch mechanics that carry a real
// report to Sentry.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/main.dart' show installAzamanFrameworkErrorHooks;

void main() {
  testWidgets('the framework error hook chains, not clobbers', (tester) async {
    final originalOnError = FlutterError.onError;

    final chainedCalls = <Object?>[];
    final recordedErrors = <Object>[];

    installAzamanFrameworkErrorHooks(
      recordFrameworkError: recordedErrors.add,
      chainedOnError: (details) => chainedCalls.add(details.exception),
    );

    try {
      const error = 'simulated-framework-error';
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: error,
          library: 'test',
          context: ErrorDescription('synthetic'),
        ),
      );

      expect(
        chainedCalls,
        [error],
        reason: 'the previously installed handler (Sentry in production) '
            'MUST receive the error — the old code clobbered it',
      );
      expect(
        recordedErrors,
        [error],
        reason: 'the app-local error record must also receive it',
      );
    } finally {
      FlutterError.onError = originalOnError;
    }
  });

  testWidgets('chaining is additive: present-error still happens for the '
      'Sentry-disabled configuration', (tester) async {
    final originalOnError = FlutterError.onError;

    // In the Sentry-disabled configuration the chained handler is the
    // framework default (presentError-equivalent) — behavior unchanged.
    var presented = 0;
    installAzamanFrameworkErrorHooks(
      recordFrameworkError: (_) {},
      chainedOnError: (_) => presented++,
    );

    try {
      FlutterError.onError!(
        const FlutterErrorDetails(
          exception: 'another-synthetic-error',
          library: 'test',
        ),
      );
      expect(presented, 1);
    } finally {
      FlutterError.onError = originalOnError;
    }
  });
}

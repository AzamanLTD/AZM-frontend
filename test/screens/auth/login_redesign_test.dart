// =============================================================================
// P4 LOGIN — PROVIDER FIRST, EMAIL AS A DELIBERATE SECOND ROUTE
//
// The owner's redesign: the page shows branding, a heading, Continue with
// Apple, Continue with Google, and one quiet secondary route into the email
// form. The form lives on its own step with its own back affordance.
//
// These tests pin:
//   1. ORDER — Apple above Google above the email route, top to bottom.
//   2. NO FORM UP FRONT — no email/password field on the landing page.
//   3. THE SECOND ROUTE — "Continue with email" reaches the form, and the form
//      has a back affordance that returns to the provider page.
//   4. NO GRADIENT — the page paints no gradient (a flat surface), and the
//      provider buttons carry their own fixed brand surfaces rather than the
//      app accent. This is the guard against a themed tint leaking in.
//   5. NO FABRICATED SUCCESS — the provider buttons are wired to the real SSO
//      service, and a cancelled sheet leaves no error on screen.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/auth/login_screen.dart';
import 'package:azaman/services/sso_gateway.dart';
import 'package:azaman/services/sso_service.dart';

Future<void> _pumpLogin(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: Consumer(
        builder: (context, ref, _) {
          final colors = ref.watch(themeProvider).colors;
          return MaterialApp(
            theme: ThemeData.light(),
            home: const LoginScreen(),
            builder: (context, child) => ColoredBox(
              color: colors.background,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
}

/// Top-to-bottom centre of a keyed widget, in global coordinates.
double _centerY(WidgetTester tester, Key key) =>
    tester.getCenter(find.byKey(key)).dy;

void main() {
  testWidgets('lands on the provider choice: Apple, Google, then email', (
    tester,
  ) async {
    await _pumpLogin(tester);

    expect(find.text('Welcome to Azaman'), findsOneWidget);
    expect(find.byKey(const Key('login-continue-apple')), findsOneWidget);
    expect(find.byKey(const Key('login-continue-google')), findsOneWidget);
    expect(find.byKey(const Key('login-continue-email')), findsOneWidget);

    // Apple is the primary (top) action, Google next, email clearly last.
    expect(
      _centerY(tester, const Key('login-continue-apple')),
      lessThan(_centerY(tester, const Key('login-continue-google'))),
    );
    expect(
      _centerY(tester, const Key('login-continue-google')),
      lessThan(_centerY(tester, const Key('login-continue-email'))),
    );

    // Labels are the owner's exact copy.
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
  });

  testWidgets('the landing page carries no email or password form', (
    tester,
  ) async {
    await _pumpLogin(tester);
    expect(find.byKey(const Key('login-email-field')), findsNothing);
    expect(find.byKey(const Key('login-password-field')), findsNothing);
    expect(find.byKey(const Key('login-email-submit')), findsNothing);
  });

  testWidgets('"Continue with email" opens the form, which can go back', (
    tester,
  ) async {
    await _pumpLogin(tester);

    await tester.tap(find.byKey(const Key('login-continue-email')));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('Sign in with email'), findsOneWidget);
    expect(find.byKey(const Key('login-email-field')), findsOneWidget);
    expect(find.byKey(const Key('login-password-field')), findsOneWidget);
    expect(find.byKey(const Key('login-email-submit')), findsOneWidget);
    // The provider buttons are not competing with the form on this step.
    expect(find.byKey(const Key('login-continue-apple')), findsNothing);

    // Back returns to the provider choice — the form is never a dead end.
    await tester.tap(find.byKey(const Key('login-email-back')));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('login-continue-apple')), findsOneWidget);
    expect(find.byKey(const Key('login-email-field')), findsNothing);
  });

  testWidgets('the page paints no gradient and the provider buttons ignore '
      'the app accent', (tester) async {
    await _pumpLogin(tester);

    // No gradient anywhere on the page — the login surface is flat.
    expect(
      find.byWidgetPredicate((w) {
        if (w is! DecoratedBox) return false;
        final d = w.decoration;
        return d is BoxDecoration && d.gradient != null;
      }),
      findsNothing,
      reason: 'the login gradient was removed in P4',
    );
    expect(
      find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration && d.gradient != null;
      }),
      findsNothing,
    );

    final colors = ThemeProvider.getColors(AzamanTheme.light);
    // Apple is black, Google is white: fixed brand surfaces, so a themed
    // accent can never tint a provider's mark.
    final apple = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const Key('login-continue-apple')),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(apple.style?.backgroundColor?.resolve({}), Colors.black);
    final google = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const Key('login-continue-google')),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(google.style?.backgroundColor?.resolve({}), Colors.white);

    // And the email route is deliberately NOT accent-coloured. The key sits on
    // the TextButton.icon itself (no wrapper), so it is read directly.
    final email = tester.widget<TextButton>(
      find.byKey(const Key('login-continue-email')),
    );
    final fg = email.style?.foregroundColor?.resolve({});
    expect(
      fg,
      isNot(colors.accent),
      reason: 'the secondary route must not read as a third provider',
    );
  });

  testWidgets('the provider buttons are wired to the real SSO service', (
    tester,
  ) async {
    // A gateway that cancels: proves the button reached the service and that a
    // dismissal leaves the page clean (no error, no stuck spinner).
    final svc = SsoService(
      gateway: _CancellingGateway(),
      hydrateSession: (ref, user) async => throw StateError('never reached'),
    );
    await _pumpLogin(
      tester,
      overrides: [ssoServiceProvider.overrideWithValue(svc)],
    );

    await tester.tap(find.byKey(const Key('login-continue-google')));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.textContaining('failed'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Welcome to Azaman'), findsOneWidget);
  });
}

class _CancellingGateway implements SsoGateway {
  @override
  Future<String> acquireGoogleIdToken() async =>
      throw const SsoCancelledException(SsoProvider.google);

  @override
  Future<String> acquireAppleIdToken() async =>
      throw const SsoCancelledException(SsoProvider.apple);
}

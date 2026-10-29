import 'dart:convert';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/kyc_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

http.Response _res(int status, Object body) =>
    http.Response(jsonEncode(body), status);

/// The light palette, taken from the app's real theme factory rather than from
/// a hand-built object, so a palette field rename shows up here as a compile
/// error instead of a silently unstyled sheet. These tests assert wording and
/// routing, not colour.
AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.light);

void main() {
  group('KycRefusal.fromResponse', () {
    test('returns null for a successful response', () {
      expect(
        KycRefusal.fromResponse(_res(200, {'success': true})),
        isNull,
      );
    });

    test('returns null for a 403 that is not an identity refusal', () {
      expect(
        KycRefusal.fromResponse(_res(403, {'code': 'BANNED', 'message': 'no'})),
        isNull,
      );
    });

    test('returns null for a non-403 status even with a KYC code', () {
      expect(
        KycRefusal.fromResponse(_res(400, {'code': 'KYC_REQUIRED'})),
        isNull,
      );
    });

    test('returns null when the body is not JSON', () {
      expect(KycRefusal.fromResponse(http.Response('<html>', 403)), isNull);
    });

    test('parses the refusal the backend actually sends', () {
      final r = KycRefusal.fromResponse(_res(403, {
        'success': false,
        'code': 'KYC_REQUIRED',
        'kycStatus': 'UNVERIFIED',
        'requiredFor': 'withdraw',
        'message': 'Verify your identity to withdraw. It takes a few minutes.',
      }));
      expect(r, isNotNull);
      expect(r!.code, 'KYC_REQUIRED');
      expect(r.status, 'UNVERIFIED');
      expect(r.action, 'withdraw');
      expect(r.needsSubmission, isTrue);
    });

    test('a pending review is not treated as "start the check"', () {
      final r = KycRefusal.fromResponse(_res(403, {
        'code': 'KYC_PENDING',
        'kycStatus': 'PENDING',
        'requiredFor': 'withdraw',
        'message': 'Your identity check is still under review.',
      }))!;
      expect(r.needsSubmission, isFalse);
      expect(r.copy.cta, 'See status');
    });
  });

  group('KycRefusal.copy', () {
    KycRefusal of(String code, String message) =>
        KycRefusal(code: code, message: message);

    test('unverified offers to start verification', () {
      final c = of('KYC_REQUIRED', 'Verify your identity to withdraw.').copy;
      expect(c.title, 'Verify your identity');
      expect(c.cta, 'Verify identity');
      // The server's sentence is echoed, not replaced by invented copy.
      expect(c.body, 'Verify your identity to withdraw.');
    });

    test('pending says under review and offers no resubmission', () {
      final c = of('KYC_PENDING', 'Still with our reviewers.').copy;
      expect(c.title, 'Verification under review');
      expect(c.cta, 'See status');
      expect(c.cta, isNot('Verify identity'));
    });

    test('rejected points at trying again', () {
      final c = of('KYC_REJECTED', 'Documents were unclear.').copy;
      expect(c.title, 'We could not verify you');
      expect(c.cta, 'Try again');
    });
  });

  group('presentKycRefusal', () {
    Future<void> pumpHost(
      WidgetTester tester,
      KycRefusal refusal,
      void Function(bool) onResult,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final went = await presentKycRefusal(
                    context,
                    refusal,
                    colors: _colors,
                  );
                  onResult(went);
                },
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
    }

    testWidgets('explains the refusal and offers the way out',
        (tester) async {
      await pumpHost(
        tester,
        const KycRefusal(
          code: 'KYC_REQUIRED',
          message: 'Verify your identity to withdraw. It takes a few minutes.',
          status: 'UNVERIFIED',
          action: 'withdraw',
        ),
        (_) {},
      );

      expect(find.text('Verify your identity'), findsOneWidget);
      expect(
        find.text('Verify your identity to withdraw. It takes a few minutes.'),
        findsOneWidget,
      );
      expect(find.text('Verify identity'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('"Not now" resolves false — the action was not taken',
        (tester) async {
      bool? result;
      await pumpHost(
        tester,
        const KycRefusal(code: 'KYC_REQUIRED', message: 'Verify to withdraw.'),
        (went) => result = went,
      );

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.text('Verify your identity'), findsNothing);
    });
  });
}

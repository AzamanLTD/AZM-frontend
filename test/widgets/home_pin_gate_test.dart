// NEW-HOME §5-6 — the Visa placeholder + the card PIN gate.
//
// The sample card must be unmistakably safe demo UI; the PIN gate must
// distinguish "Set your card PIN" (no PIN yet) from "Enter your card PIN"
// (PIN exists); the card PIN is a SEPARATE credential from the AZM account
// PIN; and sensitive card content is not exposed before the gate passes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/home/azm_visa_card.dart';

Future<void> _pumpHost(
  WidgetTester tester, {
  required AzmCardProgramme programme,
  required Future<void> Function(bool verified) onResult,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        azmCardProgrammeProvider.overrideWith((ref) => programme),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  final verified = await showCardPinGate(context);
                  await onResult(verified);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openGate(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('DemoCardProgramme (the placeholder seam)', () {
    test('starts without a PIN; set then verify works; wrong PIN fails',
        () async {
      final p = DemoCardProgramme();
      expect(p.hasPin, isFalse);

      expect(await p.setPin('1234'), isTrue);
      expect(p.hasPin, isTrue);
      expect(await p.verifyPin('1234'), isTrue);
      expect(await p.verifyPin('0000'), isFalse);
    });

    test('rejects malformed PINs instead of creating fake security state',
        () async {
      final p = DemoCardProgramme();
      expect(await p.setPin('12'), isFalse, reason: 'too short');
      expect(await p.setPin('1234567'), isFalse, reason: 'too long');
      expect(await p.setPin('12a4'), isFalse, reason: 'non-digit');
      expect(p.hasPin, isFalse);
    });

    test('the masked number is a sample, never a real credential', () {
      final p = DemoCardProgramme();
      expect(p.maskedNumber, isNot(contains(RegExp(r'\d{6}'))),
          reason: 'no six consecutive digits may appear on the sample card');
      expect(p.expiryLabel, 'MM/YY',
          reason: 'placeholder expiry — never a real date');
    });
  });

  group('CardPinGateSheet', () {
    testWidgets('no PIN yet → "Set your card PIN"; verification succeeds',
        (tester) async {
      final programme = DemoCardProgramme();
      bool? verified;
      await _pumpHost(
        tester,
        programme: programme,
        onResult: (v) async => verified = v,
      );
      await _openGate(tester);

      expect(find.text('Set your card PIN'), findsOneWidget);
      // The card PIN is explicitly a SEPARATE credential from the account
      // PIN — the copy must say so.
      expect(find.textContaining('separate from your AZM account PIN'),
          findsOneWidget);

      // Sensitive card content is NOT mounted while the gate is open.
      expect(find.byType(AzmCardDetailsPanel), findsNothing);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Set PIN'));
      await tester.pumpAndSettle();

      expect(verified, isTrue, reason: 'first PIN set → verification passes');
      expect(programme.hasPin, isTrue);
    });

    testWidgets('PIN exists → "Enter your card PIN"; a wrong attempt does '
        'not unlock', (tester) async {
      final programme = DemoCardProgramme();
      await programme.setPin('4321');
      bool? verified;
      await _pumpHost(
        tester,
        programme: programme,
        onResult: (v) async => verified = v,
      );
      await _openGate(tester);

      expect(find.text('Enter your card PIN'), findsOneWidget);

      // Wrong PIN: error, no unlock, sensitive content still not exposed.
      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('Unlock card details'));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not match'), findsOneWidget);
      expect(find.byType(AzmCardDetailsPanel), findsNothing);
      expect(verified, isNull, reason: 'the gate is still open — not verified');

      // Dismissing the sheet (barrier tap) without a successful
      // verification is a non-verification.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(verified, isFalse);
    });
  });
}

// =============================================================================
// SUPPORT / FAQ — claim-integrity tests (PR #155 review §6).
//
// Every FAQ answer must document behaviour that EXISTS in the frontend and
// backend, checked against real code on 2026-10-16:
//   • MoMo deposits are STK-push (services/moolreCollectionService.js —
//     "Send a PIN-push USSD prompt to the payer's phone")
//   • withdrawals arrive at a saved payout destination the user verifies
//     (controllers/withdrawalController.js — savedAccount.isVerified gate),
//     saved as MoMo or crypto wallet (Accounts screen hosts both)
//   • KYC is identity verification via Dojah — the withdrawal path gates on
//     VERIFIED PAYOUT ACCOUNTS, not KYC, and no KYC-linked transaction
//     limits exist, so no "raise limits / unlock withdrawals" promise
//   • AZM ID is AZM-\d{9} (services/identity/identity.service.js); lookup
//     returns exactly { azamanId, displayName, avatar } — never balances
//   • P2P escrow locks at trade ACCEPTANCE and releases on payment
//     confirmation (services/p2p.service.js); disputes exist
//     (routes/escrowRoutes.js raiseDispute)
// This test pins the corrected wording so unsupported promises cannot
// silently return.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/screens/support_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  // Tall surface: ListView.builder builds lazily, so every FAQ tile must
  // fit the viewport for question/answer assertions.
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
  await tester.pump();
}

/// Answers live inside collapsed ExpansionTiles — open every tile before
/// asserting on answer text. The deposits tile (index 0) is
/// initiallyExpanded, so tapping it would COLLAPSE it: it is skipped.
Future<void> _expandAll(WidgetTester tester) async {
  for (final q in [
    'Where do withdrawals arrive?',
    'What does verification (KYC) do?',
    'What is my AZM ID?',
    'How does a P2P trade stay safe?',
    'How do I protect my account?',
  ]) {
    await tester.tap(find.text(q));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every FAQ item renders its question', (tester) async {
    await _pump(tester);
    await _expandAll(tester);
    for (final q in [
      'How do deposits work?',
      'Where do withdrawals arrive?',
      'What does verification (KYC) do?',
      'What is my AZM ID?',
      'How does a P2P trade stay safe?',
      'How do I protect my account?',
    ]) {
      expect(find.text(q), findsOneWidget, reason: 'lost FAQ: $q');
    }
  });

  testWidgets('FAQ answers carry only VERIFIED claims', (tester) async {
    await _pump(tester);
    await _expandAll(tester);

    // The supported claims stay.
    expect(find.textContaining('STK push'), findsOneWidget);
    expect(find.textContaining('saved payout destination'), findsOneWidget);
    expect(find.textContaining('confirms your identity'), findsOneWidget);
    expect(find.textContaining('never reveals your balance'), findsOneWidget);
    expect(find.textContaining('held in escrow'), findsOneWidget);
    expect(find.textContaining('open a dispute'), findsOneWidget);
    expect(find.textContaining('biometric lock'), findsOneWidget);

    // The UNSUPPORTED promises must never render:
    // KYC does NOT raise transaction limits or unlock withdrawals — the
    // withdrawal gate is a verified payout account, not KYC.
    expect(find.textContaining('raises your transaction limits'), findsNothing);
    expect(find.textContaining('enables withdrawals'), findsNothing);
    // Escrow locks at trade acceptance — NOT "the moment you pay".
    expect(find.textContaining('locked the moment you pay'), findsNothing);
  });

  testWidgets('escrow timing documents the real lock moment', (tester) async {
    await _pump(tester);
    await _expandAll(tester);
    expect(
      find.textContaining('locked as soon as the trade is accepted'),
      findsOneWidget,
      reason: 'the escrow locks at trade acceptance, before payment',
    );
    expect(
      find.textContaining('releases when you confirm your payment'),
      findsOneWidget,
    );
  });
}

// =============================================================================
// ESCROW VAULT RAIL TESTS — TASK-016 permanent guards
//
// Pure helpers: seal destination, ring fraction (incl. honesty degenerates),
// stable seed (F-046), countdown label. Widget: held render, no-window
// honesty, terminal-on-mount post-state, live active→terminal unseal,
// reduced-motion instant path.
//
// Repeating-ticker rule: while an escrow is ACTIVE the rail runs a 1-second
// repeater, so never pumpAndSettle there — use bounded pump() calls. Once the
// escrow is terminal the repeater stops and the one-shot seal controller is
// pinned at its end value, so pumpAndSettle is safe.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/escrow_models.dart';
import 'package:azaman/widgets/escrow_vault_rail.dart';

SmartEscrow _escrow({
  EscrowStatus status = EscrowStatus.funded,
  DateTime? fundedAt,
  DateTime? expiresAt,
}) =>
    SmartEscrow(
      id: 'esc_1',
      ticketId: 'tkt_1',
      payerId: 10,
      payeeId: 20,
      amountUsdc: 100,
      feeUsdc: 2.5,
      status: status,
      payerSatisfied: false,
      payeeSatisfied: false,
      fundedAt: fundedAt,
      expiresAt: expiresAt,
    );

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 380, child: child),
          ),
        ),
      ),
    );

Widget _reducedHost(Widget child) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: SizedBox(width: 380, child: child),
            ),
          ),
        ),
      ),
    );

final _base = DateTime.utc(2026, 6, 21, 12);

void main() {
  group('escrowSealDestination', () {
    test('settled and released pay the vendor', () {
      expect(escrowSealDestination(_escrow(status: EscrowStatus.settled)),
          EscrowSealDestination.vendor);
      expect(escrowSealDestination(_escrow(status: EscrowStatus.released)),
          EscrowSealDestination.vendor);
    });

    test('refunded and expired return to the buyer', () {
      expect(escrowSealDestination(_escrow(status: EscrowStatus.refunded)),
          EscrowSealDestination.buyer);
      expect(escrowSealDestination(_escrow(status: EscrowStatus.expired)),
          EscrowSealDestination.buyer);
    });
  });

  group('escrowRingFraction', () {
    test('half-window is 0.5', () {
      final e = _escrow(
          fundedAt: _base, expiresAt: _base.add(const Duration(hours: 48)));
      expect(escrowRingFraction(e, _base.add(const Duration(hours: 24))),
          closeTo(0.5, 0.0001));
    });

    test('clamps beyond the window', () {
      final e = _escrow(
          fundedAt: _base, expiresAt: _base.add(const Duration(hours: 24)));
      expect(escrowRingFraction(e, _base.add(const Duration(hours: 30))), 1.0);
      expect(escrowRingFraction(e, _base.subtract(const Duration(hours: 1))),
          0.0);
    });

    test('missing or degenerate windows are 0 (honesty rule)', () {
      expect(escrowRingFraction(_escrow(), _base), 0.0); // no dates
      expect(
          escrowRingFraction(
              _escrow(fundedAt: _base, expiresAt: _base), _base), // zero-length
          0.0);
      expect(
          escrowRingFraction(
              _escrow(
                  fundedAt: _base,
                  expiresAt: _base.subtract(const Duration(hours: 1))),
              _base), // backwards window
          0.0);
    });
  });

  group('escrowStableSeed', () {
    test('is deterministic and matches the F-046 fold', () {
      expect(escrowStableSeed('esc_1'), escrowStableSeed('esc_1'));
      expect(escrowStableSeed('esc_1'),
          'esc_1'.codeUnits.fold<int>(7, (s, u) => s * 31 + u));
    });

    test('differs between ids', () {
      expect(escrowStableSeed('esc_1'), isNot(escrowStableSeed('esc_2')));
    });
  });

  group('escrowCountdownLabel', () {
    test('terminal states show the status label', () {
      expect(escrowCountdownLabel(_escrow(status: EscrowStatus.settled), _base),
          'Settled');
    });

    test('no window is honest', () {
      expect(escrowCountdownLabel(_escrow(), _base), 'Auto-release');
    });

    test('formats d/h, h/m, m, <1m', () {
      expect(
          escrowCountdownLabel(
              _escrow(expiresAt: _base.add(const Duration(days: 3, hours: 2))),
              _base),
          '3d 2h');
      expect(
          escrowCountdownLabel(
              _escrow(
                  expiresAt:
                      _base.add(const Duration(hours: 2, minutes: 14))),
              _base),
          '2h 14m');
      expect(
          escrowCountdownLabel(
              _escrow(expiresAt: _base.add(const Duration(minutes: 4))),
              _base),
          '4m');
      expect(
          escrowCountdownLabel(
              _escrow(expiresAt: _base.add(const Duration(seconds: 30))),
              _base),
          '<1m');
    });

    test('overdue but active is pending release', () {
      expect(
          escrowCountdownLabel(
              _escrow(expiresAt: _base.subtract(const Duration(minutes: 5))),
              _base),
          'Release pending');
    });
  });

  group('EscrowVaultRail widget', () {
    testWidgets('held escrow renders seal rim, countdown ring and parties',
        (tester) async {
      final e = _escrow(
          fundedAt: _base, expiresAt: _base.add(const Duration(hours: 24)));
      await tester.pumpWidget(_host(EscrowVaultRail(
          escrow: e, currentUserId: 10, isLoading: false)));

      expect(find.byKey(const ValueKey('escrow-seal-rim')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('escrow-countdown-ring')), findsOneWidget);
      expect(find.byKey(const ValueKey('escrow-coin-slide')), findsOneWidget);
      expect(find.text('You'), findsOneWidget); // current user is the payer
      expect(find.text('Vendor'), findsOneWidget);
      expect(find.text('100.00 USDC'), findsOneWidget);

      // The 1s repeater must keep ticking without exceptions.
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no window: ring hidden, honest label shown', (tester) async {
      await tester.pumpWidget(_host(EscrowVaultRail(
          escrow: _escrow(), currentUserId: 10, isLoading: false)));

      expect(find.byKey(const ValueKey('escrow-countdown-ring')), findsNothing);
      expect(find.text('Auto-release'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('terminal on mount renders the post-state with no animation',
        (tester) async {
      await tester.pumpWidget(_host(EscrowVaultRail(
          escrow: _escrow(status: EscrowStatus.settled),
          currentUserId: 10,
          isLoading: false)));

      // Safe here: no repeater (terminal), seal pinned at its end value.
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('escrow-seal-rim')), findsNothing);
      expect(find.byKey(const ValueKey('escrow-coin-slide')), findsNothing);
      expect(find.text('SETTLED'), findsOneWidget);
    });

    testWidgets('live active→terminal transition unseals and settles',
        (tester) async {
      final active = _escrow(
          fundedAt: _base, expiresAt: _base.add(const Duration(hours: 24)));
      await tester.pumpWidget(_host(EscrowVaultRail(
          escrow: active, currentUserId: 10, isLoading: false)));
      expect(find.byKey(const ValueKey('escrow-seal-rim')), findsOneWidget);

      // Same widget position, new escrow → didUpdateWidget, not a new State.
      await tester.pumpWidget(_host(EscrowVaultRail(
          escrow: _escrow(status: EscrowStatus.settled),
          currentUserId: 10,
          isLoading: false)));

      // Early frame: still dissolving (t ≈ 0.18 < 0.45).
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('escrow-seal-rim')), findsOneWidget);

      // Run the one-shot seal to completion, then settle.
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('escrow-seal-rim')), findsNothing);
      expect(find.byKey(const ValueKey('escrow-coin-slide')), findsNothing);
      expect(find.text('SETTLED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion completes the transition instantly',
        (tester) async {
      final active = _escrow(
          fundedAt: _base, expiresAt: _base.add(const Duration(hours: 24)));
      await tester.pumpWidget(_reducedHost(EscrowVaultRail(
          escrow: active, currentUserId: 10, isLoading: false)));
      expect(find.byKey(const ValueKey('escrow-seal-rim')), findsOneWidget);

      await tester.pumpWidget(_reducedHost(EscrowVaultRail(
          escrow: _escrow(status: EscrowStatus.settled),
          currentUserId: 10,
          isLoading: false)));

      // One frame — no animation frames under reduced motion.
      await tester.pump();
      expect(find.text('SETTLED'), findsOneWidget);
      expect(find.byKey(const ValueKey('escrow-seal-rim')), findsNothing);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

// NEW-HOME §9 — the Save / P2P / Susu wallet modules and their notice
// boards.
//
// The honesty rule: a notice board shows real contextual data ONLY when
// authoritative data is already loaded; otherwise it shows the short
// educational copy. §16: Home must NOT fetch data solely to look richer —
// reading the Save notice must not initialise the vault provider at all.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/vault_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';

class _NeverBuiltVaults extends VaultsNotifier {
  @override
  Future<List<Vault>> build() async => const [];
}

class _FakeSusuListNotifier extends SusuListNotifier {
  _FakeSusuListNotifier(this.groups);
  final List<SusuSummary> groups;
  @override
  Future<List<SusuSummary>> build() async => groups;
}

SusuSummary _activeSusu(DateTime runAt) => SusuSummary(
      id: 's1',
      name: 'Circle Susu',
      status: SusuStatus.active,
      contributionUsdc: 10,
      frequency: SusuFrequency.weekly,
      totalCycles: 10,
      nextCycle: SusuCycleSummary(
        id: 'c4',
        cycleNumber: 4,
        scheduledRunAt: runAt,
        payoutUserId: 1,
        isMe: false,
      ),
      myCycleSlot: 4,
      myStatus: SusuMemberStatus.active,
      myRole: 'MEMBER',
    );

void main() {
  testWidgets('reading the Save notice does NOT initialise the vault '
      'provider (§16: no decorative fetch)', (tester) async {
    var vaultsInitialised = false;
    final container = ProviderContainer(
      overrides: [
        vaultsProvider.overrideWith(() {
          vaultsInitialised = true;
          return _NeverBuiltVaults();
        }),
      ],
    );
    addTearDown(container.dispose);

    final notice = container.read(saveModuleNoticeProvider);
    expect(notice.populated, isFalse,
        reason: 'no vault data loaded → the educational copy shows');
    expect(
        notice.line, "Put money aside for something you're building.");
    expect(vaultsInitialised, isFalse,
        reason: 'the notice board must not trigger a vault fetch');

    // Same for a P2P read: no ads in memory → educational copy.
    final p2p = container.read(p2pModuleNoticeProvider);
    expect(p2p.populated, isFalse);
    expect(p2p.line, 'Buy or sell directly with verified vendors.');
  });

  test('a populated Susu notice reads real cycle data', () async {
    // 36h out: difference().inDays truncates, so exactly-24h would read
    // as "today" by the time the provider evaluates.
    final tomorrow = DateTime.now().add(const Duration(hours: 36));
    final container = ProviderContainer(
      overrides: [
        susuListProvider.overrideWith(
            () => _FakeSusuListNotifier([_activeSusu(tomorrow)])),
      ],
    );
    addTearDown(container.dispose);

    // Establish the watch, then let the async notifier build complete
    // before reading the resolved notice.
    container.read(susuModuleNoticeProvider);
    await Future<void>.delayed(Duration.zero);

    final notice = container.read(susuModuleNoticeProvider);
    expect(notice.populated, isTrue);
    expect(notice.line, 'Next contribution tomorrow · Cycle 4 of 10');
  });

  test('no active susu → educational copy, never a fabricated cycle',
      () async {
    final container = ProviderContainer(
      overrides: [
        susuListProvider.overrideWith(() => _FakeSusuListNotifier(const [])),
      ],
    );
    addTearDown(container.dispose);

    container.read(susuModuleNoticeProvider);
    await Future<void>.delayed(Duration.zero);

    final notice = container.read(susuModuleNoticeProvider);
    expect(notice.populated, isFalse);
    expect(notice.line, 'Save together with your circle.');
  });

  testWidgets('the row renders exactly Save / P2P / Susu with notice '
      'boards beneath', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeProvider.getThemeData(AzamanTheme.light),
          home: const MediaQuery(
            data: MediaQueryData(size: Size(400, 900)),
            child: Scaffold(body: WalletModulesRow()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('P2P'), findsOneWidget);
    expect(find.text('Susu'), findsOneWidget);
    // The educational copy is present on all three notice boards.
    expect(find.text("Put money aside for something you're building."),
        findsOneWidget);
    expect(find.text('Buy or sell directly with verified vendors.'),
        findsOneWidget);
    expect(find.text('Save together with your circle.'), findsOneWidget);
  });
}

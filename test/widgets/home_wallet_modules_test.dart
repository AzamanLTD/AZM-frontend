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
import 'package:azaman/providers/savings_overview_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/vault_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/wallet_modules.dart';

class _NeverBuiltVaults extends VaultsNotifier {
  @override
  Future<List<Vault>> build() async => const [];
}

/// A cached savings overview WITHOUT triggering the real HTTP fetch —
/// the same provider the Savings screen writes through.
class _FakeSavingsOverview extends SavingsOverviewNotifier {
  _FakeSavingsOverview(this.overviewData);
  final Map<String, dynamic> overviewData;
  @override
  Future<SavingsOverview> build() async => SavingsOverview(overviewData);
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

  testWidgets('AUDIT §6 (regression): a cached savings overview produces '
      'the REAL Save notice — goal name and progress from the SAVINGS '
      'product, never vault semantics', (tester) async {
    var vaultsInitialised = false;
    final container = ProviderContainer(
      overrides: [
        vaultsProvider.overrideWith(() {
          vaultsInitialised = true;
          return _NeverBuiltVaults();
        }),
        savingsOverviewProvider.overrideWith(
          () => _FakeSavingsOverview({
            'goals': [
              {
                'name': 'Laptop Fund',
                'currentAmountGhs': 250,
                'targetAmountGhs': 1000,
              },
              {
                'name': 'Trip to Tamale',
                'currentAmountGhs': 50,
                'targetAmountGhs': 1000,
              },
            ],
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    // The user has opened the Savings product: the overview provider is
    // INITIALISED and resolved to data (exactly what the Savings screen
    // does by writing through this same provider).
    await container.read(savingsOverviewProvider.future);
    await tester.pump();

    final notice = container.read(saveModuleNoticeProvider);

    expect(notice.populated, isTrue,
        reason: 'the savings overview IS loaded — the real copy shows');
    // The most-relevant goal (least remaining to target) drives the
    // line: Laptop Fund (750 left) beats Trip to Tamale (950 left).
    expect(notice.line, contains('Laptop'),
        reason: 'the notice names the most relevant savings goal');
    expect(notice.line, contains('25%'),
        reason: 'the notice shows the real progress (250/1000)');
    expect(notice.line, isNot(contains('vault')),
        reason: 'vault semantics never leak into the Save notice');
    expect(vaultsInitialised, isFalse,
        reason: 'a populated savings notice still never touches vaults');
  });

  testWidgets('AUDIT §6 (regression): a cached overview with no usable '
      'goal falls back to the educational copy — never a fabricated '
      'figure', (tester) async {
    final container = ProviderContainer(
      overrides: [
        savingsOverviewProvider.overrideWith(
          () => _FakeSavingsOverview({
            'goals': [
              {'name': 'No Target', 'currentAmountGhs': 40},
            ],
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Savings is initialised (cached), but the cached overview carries no
    // goal with a real target — the honest copy is still educational.
    await container.read(savingsOverviewProvider.future);
    await tester.pump();

    final notice = container.read(saveModuleNoticeProvider);
    expect(notice.populated, isFalse,
        reason: 'a goal without a target carries no real progress to '
            'show');
    expect(
        notice.line, "Put money aside for something you're building.");
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

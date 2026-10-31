// AZAMAN — WHICH CHALLENGE UNLOCKS THE MONEY
//
// The lock has one job: prove the member is present before protected money
// surfaces open. Which proof is asked for is decided HERE, in this order:
//
//   1. the method the member chose on this device for THIS account
//      ('azm.money_unlock.preferred.<userId>', a method only — never state or a
//      secret);
//   2. otherwise device authentication, when the device can do it;
//   3. otherwise the first method the BACKEND says this account configured.
//
// Availability is always a server fact. If the stored preference is not
// available any more, the sheet shows the configured alternatives instead of
// silently switching to something else.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/config.dart';
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/app_unlock_gateway.dart';
import 'package:azaman/services/money_unlock.dart';
import 'package:azaman/widgets/home/money_unlock_sheet.dart';

/// The gateway the app uses. Tests override this provider; demo builds get a
/// demo gateway that can never appear in production.
final appUnlockGatewayProvider = Provider<AppUnlockGateway>((ref) {
  if (AppConfig.demoMode && !AppConfig.isProduction) {
    // A demo BUILD is not a demo MEMBER. The seeded demo identity is the only
    // one whose PIN 1234 is a stand-in for a real unlock; an ordinary account
    // signed into a demo build must go through the real gateway, or the demo
    // PIN would be a master key for anyone who tested in that build.
    final userId = ref.watch(currentUserProvider).value?.id?.toString();
    if (userId == DemoSeedData.demoUserId) return DemoAppUnlockGateway();
  }
  return HttpAppUnlockGateway(ref.watch(apiClientProvider));
});

/// Device-specific, account-scoped preference. The METHOD only.
String moneyUnlockPreferenceKey(Object? userId) =>
    'azm.money_unlock.preferred.${userId ?? "anon"}';

/// The stored method choice, mirrored in memory.
///
/// The tap path must never wait on disk or a platform channel: an unlock tap
/// that waits for `SharedPreferences` is an unlock that can hang. So the mirror
/// is read synchronously and hydrated in the background; "not hydrated yet"
/// simply means "no preference", which falls back to device authentication.
class MoneyUnlockPreference extends Notifier<AppUnlockMethod?> {
  bool _hydrated = false;

  /// Which account the in-memory mirror currently stands for. One member's
  /// choice must not survive an account switch: the mirror is read
  /// synchronously on the tap path, so a stale value would aim the next unlock
  /// at a method this member never chose.
  String? _hydratedFor;

  @override
  AppUnlockMethod? build() => null;

  /// Called by the flow once the signed-in account is known.
  Future<void> hydrate(Object? userId) async {
    final key = moneyUnlockPreferenceKey(userId);
    if (_hydrated && _hydratedFor == key) return;
    if (_hydratedFor != null && _hydratedFor != key) {
      // Account switched: drop the previous member's choice immediately, then
      // read this one's.
      state = null;
    }
    _hydrated = true;
    _hydratedFor = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(moneyUnlockPreferenceKey(userId));
      if (raw == null) return;
      for (final method in AppUnlockMethod.values) {
        if (method.name == raw) {
          state = method;
          return;
        }
      }
    } catch (_) {
      // No readable storage: no preference. Never a reason to fail an unlock.
    }
  }

  Future<void> remember(Object? userId, AppUnlockMethod method) async {
    state = method;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(moneyUnlockPreferenceKey(userId), method.name);
    } catch (_) {
      // A convenience that failed to persist is still the choice this session.
    }
  }
}

final moneyUnlockPreferenceProvider =
    NotifierProvider<MoneyUnlockPreference, AppUnlockMethod?>(
      MoneyUnlockPreference.new,
    );

/// Runs one complete unlock attempt and returns its outcome. The caller owns
/// the generation-checked state transition: this function proves the member and
/// nothing else.
///
/// The tap path never waits on the network: a device challenge is local, so it
/// runs first when it is the answer. The capability call happens only when the
/// sheet is genuinely needed.
Future<MoneyUnlockResult> runMoneyUnlockFlow(
  BuildContext context,
  WidgetRef ref,
) async {
  final deviceAuth = ref.read(moneyUnlockCoordinatorProvider);
  final userId = ref.read(currentUserProvider).value?.id;

  // Synchronous by design (see MoneyUnlockPreference); the hydration runs in
  // the background and is picked up on the next unlock.
  final preferred = ref.read(moneyUnlockPreferenceProvider);
  unawaited(ref.read(moneyUnlockPreferenceProvider.notifier).hydrate(userId));
  if (!context.mounted) {
    return const MoneyUnlockResult(MoneyUnlockOutcome.cancelled);
  }

  final gateway = ref.read(appUnlockGatewayProvider);
  AppUnlockCapabilities? cached;
  Future<AppUnlockCapabilities>
  capabilities() async => cached ??= await () async {
    try {
      return await gateway.capabilities();
    } catch (_) {
      // Offline, signed out or a server fault: the account-scoped methods are
      // simply unknown. Never invent one.
      return AppUnlockCapabilities.none;
    }
  }();

  // 1. Device authentication, unless the member chose a server challenge.
  final wantsServerChallenge =
      preferred != null && preferred != AppUnlockMethod.deviceAuth;
  if (!wantsServerChallenge && await deviceAuth.isAvailable) {
    if (!context.mounted) {
      return const MoneyUnlockResult(MoneyUnlockOutcome.cancelled);
    }
    return deviceAuth.authenticate();
  }

  // 2. The member's own server challenge, when the account still has it.
  final caps = await capabilities();
  if (!context.mounted) {
    return const MoneyUnlockResult(MoneyUnlockOutcome.cancelled);
  }
  if (wantsServerChallenge && caps.canUse(preferred)) {
    return showMoneyUnlockSheet(
      context,
      gateway: gateway,
      capabilities: caps,
      initialMethod: preferred,
      userId: userId,
    );
  }

  // 3. Whatever the account configured — or the honest dead end.
  return showMoneyUnlockSheet(
    context,
    gateway: gateway,
    capabilities: caps,
    userId: userId,
  );
}

/// Demo builds only (never production): one known PIN so the flow is walkable
/// without a backend. The sheet labels it as a demo PIN.
class DemoAppUnlockGateway implements AppUnlockGateway {
  DemoAppUnlockGateway({this.demoPin = '1234'});

  final String demoPin;
  String? _challengeId;

  @override
  Future<AppUnlockCapabilities> capabilities() async =>
      const AppUnlockCapabilities(
        pinConfigured: true,
        authenticatorConfigured: false,
        phoneVerified: false,
        smsUnlockAvailable: false,
        smsUnavailableReason: 'PHONE_UNVERIFIED',
      );

  @override
  Future<void> verifyPin(String pin) async {
    if (pin == demoPin) return;
    throw const AppUnlockRefusal('PIN_INVALID', attemptsLeft: 4);
  }

  @override
  Future<void> verifyTotp(String token) async =>
      throw const AppUnlockRefusal('TOTP_NOT_CONFIGURED');

  @override
  Future<AppUnlockSmsChallenge> sendSmsChallenge() async =>
      throw const AppUnlockRefusal('PHONE_UNVERIFIED');

  @override
  Future<void> verifySmsChallenge({
    required String challengeId,
    required String code,
  }) async {
    if (challengeId == _challengeId) return;
    throw const AppUnlockRefusal('CHALLENGE_INVALID');
  }
}

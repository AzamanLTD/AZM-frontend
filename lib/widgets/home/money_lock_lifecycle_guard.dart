// AZAMAN — RELOCK ON A GENUINE FOREGROUND BOUNDARY
//
// Money unlocks for the current foreground session only. Backgrounding the
// app relocks it; returning to the app does NOT prompt. The member taps the
// lock when they want their money back.
//
// A native authentication sheet can itself move the app through a lifecycle
// transition. While an attempt is in flight the transition is ignored, so the
// system sheet cannot cancel — and the app cannot relock behind — a valid
// verification.
//
// The same rule applies to identity: signing out, or a different member taking
// over the device, relocks immediately. Money access belongs to one member's
// foreground session, never to the process.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/money_access_provider.dart';

/// The identity an unlock belongs to. `out` is a signed-out device.
@visibleForTesting
String moneyAccessIdentityKey(AuthProvider auth) =>
    auth.isAuthenticated ? (auth.user?.id ?? 'unknown') : 'out';

/// A changed identity always relocks. Deliberately pure so the rule is testable
/// without a live session.
@visibleForTesting
bool identityChangeRequiresRelock(String? previous, String current) =>
    previous != null && previous != current;

class MoneyLockLifecycleGuard extends ConsumerStatefulWidget {
  const MoneyLockLifecycleGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MoneyLockLifecycleGuard> createState() =>
      _MoneyLockLifecycleGuardState();
}

class _MoneyLockLifecycleGuardState
    extends ConsumerState<MoneyLockLifecycleGuard>
    with WidgetsBindingObserver {
  /// The identity the current unlock belongs to, so a change can be detected.
  String? _identityKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _identityKey = moneyAccessIdentityKey(ref.read(authProvider));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final leaving =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (!leaving) return;
    final access = ref.read(moneyAccessProvider);
    // The OS authentication sheet is not an app exit.
    if (access.isAuthenticating) return;
    access.lock();
  }

  /// Signing out or switching member relocks at once: access is never carried
  /// across an identity boundary.
  void _syncIdentity(AuthProvider auth) {
    final key = moneyAccessIdentityKey(auth);
    if (!identityChangeRequiresRelock(_identityKey, key)) {
      _identityKey = key;
      return;
    }
    _identityKey = key;
    // Signing out and switching member are the same conclusion here: the
    // unlock belonged to the previous identity, so it dies with it.
    ref.read(moneyAccessProvider).lock();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthProvider>(authProvider, (previous, next) {
      _identityKey ??= moneyAccessIdentityKey(next);
      _syncIdentity(next);
    });
    return widget.child;
  }
}

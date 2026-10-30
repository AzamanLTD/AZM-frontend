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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/money_access_provider.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  Widget build(BuildContext context) => widget.child;
}

// AZAMAN — MONEY ROUTE GUARD
//
// The gate covered Home, the history and the savings sheet. Deep links were
// the hole left: `/withdraw`, `/send`, `/deposit`, `/convert`, `/card-transfer`
// and a payment request's `/request/:token` all resolve straight to a screen
// that reads a wallet and composes a payment. A notification tap — or a link
// opened while the app sat locked in the background — would have landed the
// member on a live money composer without ever passing the Home trigger.
//
// This is the route-level answer, and it is deliberately not a redirect:
//
//   • the child is NOT BUILT while locked, so the screen's own providers never
//     run, no balance is fetched, no quote is requested, nothing is painted;
//   • the member keeps the address they came for — unlocking rebuilds in place
//     and they land on the screen the link pointed at, not back at Home;
//   • it is the same [LockedMoneySurface] as everywhere else, so the blocked
//     gesture (selection haptic, one small shake, a hint at the Home trigger)
//     is identical and does not navigate.
//
// It wraps the SCREEN, not the route table, so a route keeps its transition,
// its restoration id and its extras untouched.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/money_lock_surface.dart';

class MoneyRouteGuard extends ConsumerWidget {
  const MoneyRouteGuard({
    super.key,
    required this.child,
    this.message = 'Your money is locked',
    this.hint = 'Go back to Home and tap the Azaman button to unlock.',
  });

  final Widget child;
  final String message;
  final String hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = !ref.watch(moneyAccessProvider).canViewMoney;
    if (!locked) return child;

    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      // Back stays available: a deep link must not strand a locked member on a
      // page they cannot use. There is no primary action to offer here — the
      // unlock lives on Home, and this screen says so.
      appBar: AppBar(
        backgroundColor: colors.scaffoldBackground,
        elevation: 0,
        automaticallyImplyLeading: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: LockedMoneySurface(message: message, hint: hint),
      ),
    );
  }
}

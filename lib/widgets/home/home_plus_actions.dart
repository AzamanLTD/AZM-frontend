import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/send_money_screen.dart';
import 'package:azaman/widgets/home/plus_action_launcher.dart';
import 'package:azaman/widgets/nav_transitions.dart' as nav_transitions_pkg;

/// The Home + launcher action list (Workstream G: extracted from the
/// shell so the information architecture is pinned by tests).
///
/// Hierarchy: Send / Receive stay the primary (gold) actions; Add Cash,
/// Withdraw and Convert are secondary (neutral chip).
///
/// Convert is the honest entry: it routes to the real `/convert` shell,
/// whose execution is capability-gated until the backend ships a
/// verified conversion contract. It is never a toast and never a
/// display-preference switch.
List<PlusLauncherAction> buildHomePlusActions(BuildContext context) {
  return [
    PlusLauncherAction(
      // PASS F1 — the rounded arrow-head style from the existing
      // Hugeicons family: Send points outward (up-right, away),
      // Receive points inward (down-left, toward you). Primary actions
      // (pass E): bright gold.
      icon: HugeIconsSolid.arrowUpRight01,
      prominent: true,
      label: 'Send',
      onTap: () => nav_transitions_pkg.pushWithVerticalTransition(
        context,
        const SendMoneyScreen(),
      ),
    ),
    PlusLauncherAction(
      icon: HugeIconsSolid.arrowDownLeft01,
      prominent: true,
      label: 'Receive',
      onTap: () => showReceiveSheet(context),
    ),
    PlusLauncherAction(
      // PASS E — gold hierarchy: secondary actions carry the NEUTRAL
      // chip; bright gold stays reserved for Send/Receive.
      icon: HugeIconsSolid.wallet01,
      label: 'Add Cash',
      // CANONICAL ROUTE: /deposit owns the rise transition at the route
      // level (risePage) — the launcher pushes the location, never a
      // bare MaterialPageRoute-equivalent.
      onTap: () => context.push(AzRoutes.deposit()),
    ),
    PlusLauncherAction(
      icon: HugeIconsSolid.bank,
      label: 'Withdraw',
      // CANONICAL ROUTE: /withdraw (Workstream C) — same rise semantics as
      // Add Cash, routed so every entry point transitions alike.
      onTap: () => context.push(AzRoutes.withdraw()),
    ),
    PlusLauncherAction(
      // Workstream G — Convert: a real navigation action to the honest
      // conversion shell. Secondary tier, an existing exchange icon from
      // the Hugeicons family; no custom art, no new hierarchy.
      icon: HugeIconsSolid.exchange01,
      label: 'Convert',
      onTap: () => context.push(AzRoutes.convert()),
    ),
  ];
}

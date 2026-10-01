// =============================================================================
// AZAMAN — MOMO NETWORK IDENTITY  (single source of truth)
//
// ── WHY ──────────────────────────────────────────────────────────────────────
// Before this file, every surface that rendered a Ghana mobile-money network
// hand-rolled its own provider mapping — and they disagreed:
//
//   • deposit_screen._SavedAccountTile._providerColor()  had TWO 'TELECEL'
//     cases (the second — the correct Telecel blue — was dead code), and no
//     AIRTELTIGO case at all.
//   • saved_momo_accounts_screen._MomoTile._providerColor()  carried the same
//     duplicated dead 'TELECEL' case.
//   • saved_wallets_screen._loadAccounts()  had a dead second 'TELECEL' case
//     that — had it ever been reached — would have mapped Telecel accounts to
//     AIRTELTIGO.
//   • withdrawal_screen used a third, different AIRTELTIGO red.
//
// This module is the ONE authoritative mapping. Surfaces must render network
// identity from here, never from a local switch.
//
// ── LEGACY VALUES ─────────────────────────────────────────────────────────────
// Saved accounts may still carry the pre-rebrand 'VODAFONE' / 'VODAFONE_CASH'
// values (Vodafone Ghana became Telecel in 2023). They present as TELECEL
// everywhere in the UI. The backend treats the two as the same channel.
//
// ── NO FABRICATED LOGOS ───────────────────────────────────────────────────────
// There is no licensed network logo asset in the repo, so [MomoNetworkBadge]
// renders a neutral identity mark using the network's brand color and its code
// (MTN / TEL / AT) — deliberately NOT an invented official-looking logo.
// =============================================================================

import 'package:flutter/material.dart';

class MomoNetworkInfo {
  const MomoNetworkInfo({
    required this.id,
    required this.displayName,
    required this.code,
    required this.color,
    required this.semanticsLabel,
  });

  /// Canonical id: `MTN` | `TELECEL` | `AIRTELTIGO` | `OTHER`.
  final String id;

  /// Human-facing product name: `MTN MoMo`, `Telecel Cash`, `AirtelTigo Money`.
  final String displayName;

  /// Short badge text: `MTN`, `TEL`, `AT`.
  final String code;

  /// The network's brand color — backgrounds must wash it, never flood it.
  final Color color;

  /// Screen-reader identity, e.g. `MTN Mobile Money`.
  final String semanticsLabel;

  bool get isKnown => id != 'OTHER';
}

abstract final class MomoNetwork {
  const MomoNetwork._();

  // Brand colors, consistent across every surface (deposit, saved accounts,
  // saved wallets). These match the values the app already shipped for the
  // two networks it rendered correctly (withdrawal / saved-wallets picks).
  static const Color mtnYellow = Color(0xFFFFCC00);
  static const Color telecelRed = Color(0xFFE60000);
  static const Color airtelTigoRed = Color(0xFFD62828);

  static const MomoNetworkInfo _mtn = MomoNetworkInfo(
    id: 'MTN',
    displayName: 'MTN MoMo',
    code: 'MTN',
    color: mtnYellow,
    semanticsLabel: 'MTN Mobile Money',
  );

  static const MomoNetworkInfo _telecel = MomoNetworkInfo(
    id: 'TELECEL',
    displayName: 'Telecel Cash',
    code: 'TEL',
    color: telecelRed,
    semanticsLabel: 'Telecel Mobile Money',
  );

  static const MomoNetworkInfo _airteltigo = MomoNetworkInfo(
    id: 'AIRTELTIGO',
    displayName: 'AirtelTigo Money',
    code: 'AT',
    color: airtelTigoRed,
    semanticsLabel: 'AirtelTigo Mobile Money',
  );

  /// Unknown providers still render (they may be a network the backend knows
  /// but the design system has no identity for) — neutral mark, no fake brand.
  static const MomoNetworkInfo _other = MomoNetworkInfo(
    id: 'OTHER',
    displayName: 'Mobile Money',
    code: 'MM',
    color: Color(0xFF888888),
    semanticsLabel: 'Mobile Money',
  );

  /// The one provider→identity mapping. Accepts both the canonical saved-
  /// account values (MTN | TELECEL | AIRTELTIGO) and the backend enum values
  /// (MTN_MOMO | TELECEL_CASH | AIRTELTIGO), plus legacy VODAFONE variants.
  static MomoNetworkInfo of(String provider) {
    switch (provider.trim().toUpperCase()) {
      case 'MTN':
      case 'MTN_MOMO':
        return _mtn;
      case 'TELECEL':
      case 'TELECEL_CASH':
      case 'VODAFONE': // legacy — Vodafone Ghana is now Telecel
      case 'VODAFONE_CASH':
        return _telecel;
      case 'AIRTELTIGO':
      case 'AT':
        return _airteltigo;
      default:
        return _other;
    }
  }

  /// Ghana mobile number, presented the way Ghanaians read them:
  /// `+233244123456` → `024 412 3456`. Accepts E.164 with or without the
  /// leading `+`, and already-local `0…` forms. Anything that is not a
  /// recognisable Ghana mobile number is returned trimmed but unchanged —
  /// this formatter never invents digits.
  static String formatPhone(String raw) {
    var digits = raw.trim();
    if (digits.startsWith('+233')) {
      digits = '0${digits.substring(4)}';
    } else if (digits.startsWith('233') && digits.length == 12) {
      digits = '0${digits.substring(3)}';
    }
    if (digits.length != 10 || !digits.startsWith('0')) {
      return digits; // not a Ghana mobile shape — show it honestly
    }
    final local = digits.replaceAll(RegExp(r'\D'), '');
    if (local.length != 10) return digits;
    return '${local.substring(0, 3)} ${local.substring(3, 6)} '
        '${local.substring(6)}';
  }
}

/// A small circular network identity mark: brand-color wash, short code.
/// Not a logo — a deliberate, honest identity badge (see header).
///
/// Exposes the network's semantics label so screen readers announce the
/// network identity, not the code glyphs.
class MomoNetworkBadge extends StatelessWidget {
  const MomoNetworkBadge({
    super.key,
    required this.provider,
    this.size = 40,
    this.showLabel = true,
  });

  final String provider;
  final double size;

  /// When false the badge is purely decorative inside a row that already
  /// carries the network semantics itself.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final network = MomoNetwork.of(provider);
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: network.color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: network.color.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Text(
        network.code,
        style: TextStyle(
          color: network.color,
          fontSize: size * 0.30,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
          height: 1.0,
        ),
      ),
    );
    if (!showLabel) return mark;
    return Semantics(
      label: network.semanticsLabel,
      button: false,
      excludeSemantics: true,
      child: mark,
    );
  }
}

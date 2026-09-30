// =============================================================================
// AZ GREETING BRAIN  (NEW-D)
//
// Home's top 60px stops being a string and becomes the app's VOICE.
//
// Priority order (highest first). Money events always beat pleasantries,
// because a user who just got paid does not want "Good morning":
//
//   1. moneyArrivedToday        → "Your USDC 400.00 cleared"
//   2. escrowReleasingInHours   → "Escrow releases in 3h"
//   3. susuDueTomorrow          → "Susu due tomorrow"
//   4. depositAwaitingApproval  → "Waiting on your mobile-money approval"
//   5. time of day              → "Good morning" / "afternoon" / "evening"
//
// HONESTY RULES (F.5 / NEW-T / §H.7): every input is nullable and NOTHING is
// invented. An unknown value skips its line. No invented payday, and no
// greeting that names an amount the app cannot verify.
//
// §H.7: streaks are deliberately NOT an input. A flame next to a bank
// balance reads as pressure, and this resolver has no warming tone and no
// fire glyph for that reason.
// =============================================================================

import 'package:flutter/material.dart';

enum AzGreetingTone { neutral, positive, attention }

class AzGreetingLine {
  final String text;

  /// Drives the glyph shown beside the greeting.
  final AzGreetingTone tone;

  /// True only for a REAL event that just happened — the only case that may
  /// announce itself with a haptic or a sound (TASK-020's pairing rule).
  final bool announceable;

  const AzGreetingLine({
    required this.text,
    this.tone = AzGreetingTone.neutral,
    this.announceable = false,
  });
}

class AzGreetingInputs {
  /// The identity Home already reads (authProvider's username).
  final String? username;
  final DateTime now;

  /// A settled inflow today, already formatted by `AzMoney`. Null when no
  /// verified settled inflow exists — never a made-up amount.
  final String? moneyArrivedToday;

  /// Hours until the next escrow release (null when none / unknown).
  /// Negative values are in the past and are skipped.
  final int? escrowReleasingInHours;

  /// True only when an authoritative Susu source says a collection is
  /// scheduled for tomorrow.
  final bool susuDueTomorrow;

  /// True only when an authoritative deposit source says a deposit is
  /// accepted-but-not-settled.
  final bool depositAwaitingApproval;

  const AzGreetingInputs({
    required this.now,
    this.username,
    this.moneyArrivedToday,
    this.escrowReleasingInHours,
    this.susuDueTomorrow = false,
    this.depositAwaitingApproval = false,
  });
}

abstract class AzGreetingBrain {
  static AzGreetingLine resolve(AzGreetingInputs i) {
    final arrived = i.moneyArrivedToday;
    if (arrived != null && arrived.isNotEmpty) {
      return AzGreetingLine(
        text: 'Your $arrived cleared',
        tone: AzGreetingTone.positive,
        announceable: true,
      );
    }
    final hours = i.escrowReleasingInHours;
    if (hours != null && hours >= 0) {
      return AzGreetingLine(
        text: hours == 0
            ? 'Escrow releases now'
            : 'Escrow releases in ${_hours(hours)}',
        tone: AzGreetingTone.attention,
      );
    }
    if (i.susuDueTomorrow) {
      return const AzGreetingLine(
        text: 'Susu due tomorrow',
        tone: AzGreetingTone.attention,
      );
    }
    if (i.depositAwaitingApproval) {
      return const AzGreetingLine(
        text: 'Waiting on your mobile-money approval',
        tone: AzGreetingTone.attention,
      );
    }
    return AzGreetingLine(
      text: '${_partOfDay(i.now)}, ${_name(i.username)}',
      tone: AzGreetingTone.neutral,
    );
  }

  /// "1h" / "3h" / "under an hour" — never "in 0h", never a negative
  /// duration (negatives are skipped before this is reached).
  static String _hours(int h) {
    if (h < 1) return 'under an hour';
    if (h == 1) return '1h';
    return '${h}h';
  }

  static String _partOfDay(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _name(String? username) {
    final n = (username ?? '').trim();
    if (n.isEmpty) return 'there'; // never a dangling comma, never "null"
    // First name only: "Good morning, Kwame" reads like a person; a full
    // legal name reads like a bank statement.
    return n.split(RegExp(r'\s+')).first;
  }

  /// Which glyph the header shows. Kept here so the widget stays dumb.
  /// §H.7: no warming/flame glyph exists in this set by design.
  static IconData glyphFor(AzGreetingTone tone) {
    switch (tone) {
      case AzGreetingTone.positive:
        return Icons.trending_up_rounded;
      case AzGreetingTone.attention:
        return Icons.schedule_rounded;
      case AzGreetingTone.neutral:
        return Icons.wb_sunny_outlined;
    }
  }
}

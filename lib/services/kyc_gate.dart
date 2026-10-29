import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../providers/theme_provider.dart';
import '../screens/kyc_verification_screen.dart';

/// A financial action refused because the account is not identity-verified.
///
/// The backend enforces this at the money boundary (`middleware/requireKyc.js`)
/// and answers `403` with a `KYC_*` code. The client's job is not to police the
/// action — the server already did — but to explain it in the user's language
/// and put the fix one tap away, so a refused withdrawal is a redirect instead
/// of a dead end with a red snackbar.
class KycRefusal {
  const KycRefusal({
    required this.code,
    required this.message,
    this.status,
    this.action,
  });

  /// `KYC_REQUIRED`, `KYC_PENDING` or `KYC_REJECTED`.
  final String code;
  final String message;

  /// The server's view of the account: UNVERIFIED / PENDING / REJECTED.
  final String? status;

  /// The action that was attempted, e.g. `withdraw`.
  final String? action;

  /// Returns null for anything that is not an identity refusal — including a
  /// 403 for some other reason — so callers keep their existing behaviour.
  static KycRefusal? fromResponse(http.Response response) {
    if (response.statusCode != 403) return null;
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      data = decoded;
    } catch (_) {
      return null;
    }
    final code = data['code']?.toString() ?? '';
    if (!code.startsWith('KYC_')) return null;
    return KycRefusal(
      code: code,
      message: data['message']?.toString() ??
          'Verify your identity to continue.',
      status: data['kycStatus']?.toString(),
      action: data['requiredFor']?.toString(),
    );
  }

  /// True when the user still has to start the check, as opposed to waiting on
  /// a review that is already under way. Drives which call to action we offer.
  bool get needsSubmission => code != 'KYC_PENDING';

  /// Title + body in plain language. The server's message is deliberately
  /// echoed rather than reinvented: it is the one string that already knows
  /// whether this is "not started", "under review" or "rejected".
  ({String title, String body, String cta}) get copy {
    switch (code) {
      case 'KYC_PENDING':
        return (
          title: 'Verification under review',
          body: message,
          cta: 'See status',
        );
      case 'KYC_REJECTED':
        return (
          title: 'We could not verify you',
          body: message,
          cta: 'Try again',
        );
      default:
        return (
          title: 'Verify your identity',
          body: message,
          cta: 'Verify identity',
        );
    }
  }
}

/// Shows the refusal and offers the route to fix it.
///
/// Resolves to true when the user chose to go and verify (so the caller knows
/// the action was deliberately deferred, not silently dropped).
Future<bool> presentKycRefusal(
  BuildContext context,
  KycRefusal refusal, {
  required AzamanColors colors,
}) async {
  final c = colors;
  final wording = refusal.copy;

  final wentToVerify = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 20, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  wording.title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            wording.body,
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text(
                    'Not now',
                    style: TextStyle(color: c.textTertiary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: c.accent),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: Text(wording.cta),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  if (wentToVerify != true || !context.mounted) return false;

  // The KYC screen owns its own submit/poll lifecycle; it pops when the user
  // leaves it. We do NOT assume verification succeeded — the user returns to
  // the action and the server's verdict (not this screen) decides.
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const KycVerificationScreen()),
  );
  return true;
}

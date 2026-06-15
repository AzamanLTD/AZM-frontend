// =============================================================================
// INVITE LANDING SCREEN — Phase 4 (Master Sprint, 2026-05-31)
//
// Public-route screen reached via the shared private invite URL
// `https://azaman.app/susu/invite/:token` and the local GoRoute
// `/susu/invite/:token`. Calls `/api/susu/invites/preview/:token`
// without a JWT — this is the only Susu endpoint that is public.
//
// Branching:
//   • Token expired/used (HTTP 410) → friendly "no longer valid" message
//   • Caller authenticated → "Accept" button calls /redeem and routes to
//     the new dashboard. KYC / PoR gating is enforced server-side; on
//     KYC_REQUIRED / RESIDENCY_REQUIRED we show inline next-step CTAs.
//   • Caller unauthenticated → SnackBar prompting login. We preserve
//     the token in the deep-link so the post-login flow can resume.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/susu_service.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class InviteLandingScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteLandingScreen({super.key, required this.token});

  @override
  ConsumerState<InviteLandingScreen> createState() =>
      _InviteLandingScreenState();
}

class _InviteLandingScreenState extends ConsumerState<InviteLandingScreen> {
  bool _redeeming = false;

  Future<void> _redeem() async {
    final user = ref.read(authProvider).user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Sign in or create an account first, then re-open this invite link.'),
        ),
      );
      // Pop back to splash/login. The token stays in the route so the
      // user can return to it after auth.
      context.go('/');
      return;
    }
    setState(() => _redeeming = true);
    try {
      final susuId = await susuService.redeemLink(widget.token);
      if (!mounted) return;
      ref.invalidate(susuListProvider);
      // Land on the new dashboard. The contract acceptance CTA is on
      // the dashboard itself (the member is now PENDING_CONTRACT).
      context.pushReplacement('/susu/$susuId');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept invite: $e')),
      );
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final preview = ref.watch(susuInvitePreviewProvider(widget.token));
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01,
              color: colors.textPrimary, size: 18),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Text(
          'Susu invite',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: preview.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: colors.warning),
          ),
          error: (e, _) {
            final msg = e.toString();
            final expired =
                msg.contains('410') || msg.contains('INVITE_EXPIRED_OR_USED');
            return _ErrorView(
              error: e,
              expired: expired,
              colors: colors,
            );
          },
          data: (p) => _PreviewBody(
            preview: p,
            colors: colors,
            isAuthed: user != null,
            redeeming: _redeeming,
            onRedeem: _redeem,
          ),
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  final SusuInvitePreview preview;
  final AzamanColors colors;
  final bool isAuthed;
  final bool redeeming;
  final VoidCallback onRedeem;
  const _PreviewBody({
    required this.preview,
    required this.colors,
    required this.isAuthed,
    required this.redeeming,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final pool = preview.contributionUsdc * preview.memberCount;
    final exp = preview.expiresAt.toLocal();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.warning.withOpacity(0.18),
                colors.accent.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: colors.warning.withOpacity(0.30), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(HugeIconsSolid.bank,
                      color: colors.warning, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      preview.susuName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Invited by @${preview.inviterDisplayName}',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '\$${preview.contributionUsdc.toStringAsFixed(2)}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              Text(
                'per cycle · ${preview.frequency.label} · '
                '${preview.memberCount} members · '
                '\$${pool.toStringAsFixed(2)} expected pool',
                style: TextStyle(color: colors.textTertiary, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Before you accept',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              _BulletRow(
                colors: colors,
                icon: HugeIconsSolid.shield01,
                text: 'You will need a verified ID (KYC) and proof of '
                    'residency before joining.',
              ),
              _BulletRow(
                colors: colors,
                icon: HugeIconsSolid.judge,
                text: 'A liability contract authorises automatic seizure '
                    'of contributions on cycle days.',
              ),
              _BulletRow(
                colors: colors,
                icon: HugeIconsSolid.shield01,
                text: 'Your inviter loses AZM and trust rating if you '
                    'default — vouching is permanent.',
              ),
              _BulletRow(
                colors: colors,
                icon: HugeIconsSolid.clock01,
                text: 'This invite expires '
                    '${exp.year}-${exp.month.toString().padLeft(2, '0')}-${exp.day.toString().padLeft(2, '0')} '
                    '${exp.hour.toString().padLeft(2, '0')}:${exp.minute.toString().padLeft(2, '0')}.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: redeeming ? null : onRedeem,
            icon: redeeming
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(HugeIconsSolid.checkmarkCircle01, size: 16),
            label: Text(
              redeeming
                  ? 'Accepting…'
                  : isAuthed
                      ? 'Accept invite'
                      : 'Sign in to continue',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.warning,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String text;
  const _BulletRow({
    required this.colors,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.warning, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final bool expired;
  final AzamanColors colors;
  const _ErrorView({
    required this.error,
    required this.expired,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expired
                  ? HugeIconsSolid.clock01
                  : HugeIconsSolid.alertCircle,
              size: 48,
              color: expired ? colors.warning : colors.danger,
            ),
            const SizedBox(height: 12),
            Text(
              expired
                  ? 'Invite no longer valid'
                  : 'Could not load invite',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              expired
                  ? 'This single-use link has expired or already been '
                      'redeemed. Ask the inviter to send a new one.'
                  : error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// VOUCH FORM SCREEN  (Master Sprint, 2026-05-27)
//
// Mandatory vouch form rendered when a member needs to vouch for an
// invitee. Lives at /susu/vouches/pending. Both inviter and second
// voucher use this same form — the difference is just whether the
// VouchRecord row was created with isInviter=true.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';


class VouchFormScreen extends ConsumerStatefulWidget {
  final PendingVouch vouch;
  const VouchFormScreen({super.key, required this.vouch});

  @override
  ConsumerState<VouchFormScreen> createState() => _VouchFormScreenState();
}

class _VouchFormScreenState extends ConsumerState<VouchFormScreen> {
  final _relationship = TextEditingController();
  final _duration = TextEditingController();
  final _reason = TextEditingController();
  bool _ackPenalty = false;
  bool _busy = false;

  @override
  void dispose() {
    _relationship.dispose();
    _duration.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_relationship.text.trim().isEmpty ||
        _reason.text.trim().isEmpty ||
        !_ackPenalty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill out all fields and confirm the penalty clause.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(susuActionsProvider).submitVouch(widget.vouch.id, {
        'relationship': _relationship.text.trim(),
        'durationKnown': _duration.text.trim().isEmpty ? 'unspecified' : _duration.text.trim(),
        'reasonForTrust': _reason.text.trim(),
        'acknowledgesPenalty': true,
      });
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final inviteeLabel = widget.vouch.inviteeUsername ??
        widget.vouch.inviteePhone ??
        'this user';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Vouch Form',
            style: TextStyle(
                color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.warning.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: colors.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You are vouching for $inviteeLabel. If they default on a Susu, your trust score takes a penalty across every Susu you participate in.',
                    style: TextStyle(
                      color: colors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _label(colors, 'Real-world Relationship'),
          _input(colors, _relationship, hint: 'cousin, co-worker, neighbour…'),
          const SizedBox(height: 12),
          _label(colors, 'How Long You\'ve Known Them'),
          _input(colors, _duration, hint: '3 years'),
          const SizedBox(height: 12),
          _label(colors, 'Why You Trust Them'),
          _input(
            colors,
            _reason,
            hint: 'Specific reasons. Vague answers will be rejected.',
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          CheckboxListTile.adaptive(
            value: _ackPenalty,
            onChanged: (v) => setState(() => _ackPenalty = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: colors.warning,
            title: Text(
              'I accept the trust-score penalty if this user defaults.',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.warning,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(
                _busy ? 'Submitting…' : 'Submit Vouch',
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(AzamanColors colors, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          s.toUpperCase(),
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _input(AzamanColors colors, TextEditingController c,
      {String? hint, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      ),
    );
  }
}

// lib/screens/marketplace/leave_review_sheet.dart
// =============================================================================
// LEAVE A REVIEW SHEET — Marketplace Premium Upgrade (2026-06-21)
//
// Modal bottom sheet for submitting a star rating + written review.
// Backend: POST /api/business/reviews
//   body: { businessProfileId, rating (1-5), comment (optional) }
// Requires: the user must have a completed order from this business
//   (the backend enforces this via protectActive middleware).
//
// Usage:
//   final submitted = await LeaveReviewSheet.show(context, business: b);
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/widgets/animated_rating_stars.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/services/az_sound.dart';
import 'package:azaman/widgets/azaman_sheet.dart';

class LeaveReviewSheet extends ConsumerStatefulWidget {
  final BusinessProfile business;
  const LeaveReviewSheet({super.key, required this.business});

  static Future<bool> show(BuildContext context, {required BusinessProfile business}) async {
    // Panel, not Whisper: the body is keyboard-bound (a 4-line TextField plus
    // a keyboard-inset padding) and the comment is free text the user types, so
    // the height is not bounded by a constant. The commit row is gated on a
    // rating, so it is pinned — a disabled button that scrolls away is an
    // instruction the user cannot see.
    final result = await AzamanSheet.showPanel<bool>(
      context,
      builder: (_, __) => LeaveReviewSheet(business: business),
    );
    return result ?? false;
  }

  @override
  ConsumerState<LeaveReviewSheet> createState() => _LeaveReviewSheetState();
}

class _LeaveReviewSheetState extends ConsumerState<LeaveReviewSheet> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;
  String? _reviewId;
  bool _sharing = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Please select a star rating.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await BusinessService().createReview({
        'businessProfileId': widget.business.id,
        'rating': _rating,
        'comment': _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
      });
      AzamanHaptics.commit();
      AzSound.success();
      if (mounted) {
        setState(() {
          _submitted = true;
          _reviewId = result.id;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final onAccent = colors.isDark ? Colors.black : Colors.white;
    // The weight owns the surface, the radius and the safe-area; the body owns
    // its content only. Keyboard inset is the one thing the shell does not
    // supply, so it is applied here on the pinned footer.
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AzSpace.xl, AzSpace.lg, AzSpace.xl, AzSpace.md),
            children: [
              Text(
                'Rate ${widget.business.businessName}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Share your experience with this business.',
                style: TextStyle(color: colors.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              // Star row
              Center(
              child: AnimatedRatingStars.interactive(
                initialRating: _rating.toDouble(), size: 40,
                onRatingChanged: (r) => setState(() => _rating = r.toInt()),
                filledColor: colors.accent,
              ),
              ),
              if (_rating > 0) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    _ratingLabel(_rating),
                    style: TextStyle(
                      color: colors.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _commentCtrl,
                maxLines: 4,
                maxLength: 500,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Write a review (optional)…',
                  hintStyle: TextStyle(color: colors.textTertiary),
                  filled: true,
                  fillColor: colors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: colors.danger, fontSize: 13)),
              ],
              // ── Share as Story option (Marketplace Overhaul 2026-07-02) ──
              // Lives in the scroll flow, above the commit row: it only exists
              // after a successful submit, so it is never the thing the user is
              // looking for on first open.
              if (_submitted) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.celebration, color: colors.accent, size: 32),
                      const SizedBox(height: 8),
                      Text('Review submitted!',
                          style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Share your review as a Story so friends can discover this business.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _sharing ? null : () async {
                                setState(() => _sharing = true);
                                try {
                                  if (_reviewId != null) {
                                    await ref.read(marketplaceBookingServiceProvider).promoteReviewToStory(_reviewId!);
                                  }
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: const Text('Shared as Story!'), backgroundColor: colors.accent),
                                  );
                                  if (context.mounted) Navigator.pop(context, true);
                                } catch (e) {
                                  if (!context.mounted) return;
                                  setState(() => _sharing = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Could not share: $e')),
                                  );
                                }
                              },
                              icon: _sharing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(Icons.share, color: colors.accent),
                              label: Text('Share as Story', style: TextStyle(color: colors.accent)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text('Not now', style: TextStyle(color: colors.textSecondary)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // ── Pinned commit row (§I.8.3) ──────────────────────────────────
        // The submit action is GATED on a rating. Left inside the scroll flow
        // the user would scroll to the bottom and meet a greyed-out button
        // with no explanation. Pinned, the disabled button is visible from the
        // first frame and its state is the instruction. It also carries the
        // keyboard inset, which is the one thing the weight does not supply.
        Container(
          padding: EdgeInsets.fromLTRB(
            AzSpace.xl,
            AzSpace.md,
            AzSpace.xl,
            AzSpace.md + keyboard,
          ),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.divider)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_rating == 0 || _submitting) ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: onAccent,
                disabledBackgroundColor: colors.softSurface,
                disabledForegroundColor: colors.textTertiary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: onAccent,
                      ),
                    )
                  : Text(
                      _submitted ? 'Update review' : 'Submit review',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  String _ratingLabel(int r) {


    switch (r) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }
}

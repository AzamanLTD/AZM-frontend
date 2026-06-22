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
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class LeaveReviewSheet extends ConsumerStatefulWidget {
  final BusinessProfile business;
  const LeaveReviewSheet({super.key, required this.business});

  static Future<bool> show(BuildContext context, {required BusinessProfile business}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LeaveReviewSheet(business: business),
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
      await BusinessService().createReview({
        'businessProfileId': widget.business.id,
        'rating': _rating,
        'comment': _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
      });
      AzamanHaptics.commit();
      if (mounted) Navigator.pop(context, true);
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Rate ${widget.business.businessName}',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Share your experience with this business.',
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            // Star row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () {
                    AzamanHaptics.toggle();
                    setState(() => _rating = star);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      HugeIconsSolid.star,
                      size: 38,
                      color: star <= _rating ? colors.warning : colors.divider,
                    ),
                  ),
                );
              }),
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
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: onAccent,
                  elevation: 0,
                  disabledBackgroundColor: colors.accent.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: onAccent,
                        ),
                      )
                    : const Text(
                        'Submit Review',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
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

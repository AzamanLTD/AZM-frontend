// =============================================================================
// TRADE SUMMARY SCREEN — Phase O | Azaman V2
//
// Post-trade completion summary with peer review submission.
// Phase O: migrated from hardcoded dark colors to themeProvider palette so
// this screen respects the user's active theme (was the last holdout).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/receipt_service.dart';
import 'package:azaman/services/api_client.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class TradeSummaryScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> tradeData;
  final bool isVendor; // To customize the text based on who is looking at it

  const TradeSummaryScreen({
    super.key,
    required this.tradeData,
    this.isVendor = false,
  });

  @override
  ConsumerState<TradeSummaryScreen> createState() => _TradeSummaryScreenState();
}

class _TradeSummaryScreenState extends ConsumerState<TradeSummaryScreen> {
  bool? _isPositive; // true = Thumbs Up, false = Thumbs Down, null = unselected
  final TextEditingController _commentController = TextEditingController();
  
  bool _isSubmitting = false;
  bool _hasReviewed = false; // To hide the review box once submitted
  bool _isDownloadingReceipt = false;

  Future<void> _submitReview() async {
    final colors = ref.read(themeProvider).colors;
    if (_isPositive == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Please select Thumbs Up or Thumbs Down"),
          backgroundColor: colors.danger,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final cleanId = widget.tradeData['tradeId'].toString().replaceAll('#', '');

      final response = await apiClient.post('/trades/review', {
        "tradeId": cleanId,
        "isPositive": _isPositive,
        "comment": _commentController.text.trim(),
      });

      if (response.statusCode == 201) {
        HapticFeedback.heavyImpact();
        setState(() => _hasReviewed = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Review submitted! Thank you."),
              backgroundColor: colors.success,
            ),
          );
        }
      }
    } on ApiException catch (e) {
      // Handle "already reviewed" gracefully
      if (e.statusCode == 400 && e.message.contains("already")) {
        setState(() => _hasReviewed = true);
      } else {
        _showError(e.message);
      }
    } catch (e) {
      _showError("Network Error. Please try again.");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      final colors = ref.read(themeProvider).colors;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: colors.danger),
      );
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    // Format the date if available, otherwise use 'Just now'
    final dateObj = widget.tradeData['completedAt'] != null 
        ? DateTime.parse(widget.tradeData['completedAt']).toLocal() 
        : DateTime.now();
    final String formattedDate = "${dateObj.year}-${dateObj.month.toString().padLeft(2,'0')}-${dateObj.day.toString().padLeft(2,'0')} ${dateObj.hour.toString().padLeft(2,'0')}:${dateObj.minute.toString().padLeft(2,'0')}";

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false, // Force them to use the "Done" button at the bottom
        title: Text(
          "Order Completed",
          style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildSuccessHeader(colors),
                    const SizedBox(height: 30),
                    _buildReceiptCard(formattedDate, colors),
                    const SizedBox(height: 16),
                    _buildDownloadReceiptButton(colors),
                    const SizedBox(height: 8),
                    _statusTimeline(colors),
                    const SizedBox(height: 30),
                    if (!_hasReviewed)
                      _buildReviewSection(colors)
                    else
                      _buildThankYouCard(colors),
                  ],
                ),
              ),
            ),
            _buildBottomBar(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessHeader(AzamanColors colors) {
    return Column(
      children: [
        Container(
          height: 80,
          width: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.success.withOpacity(0.1),
            border: Border.all(color: colors.success, width: 2),
          ),
          child: Icon(HugeIconsSolid.checkmarkCircle01, color: colors.success, size: 50),
        ),
        const SizedBox(height: 20),
        Text(
          widget.isVendor ? "Successfully Sold" : "Successfully Bought",
          style: TextStyle(color: colors.textSecondary, fontSize: 16),
        ),
        const SizedBox(height: 5),
        Text(
          widget.isVendor 
              ? "\$${widget.tradeData['amountCrypto'] ?? widget.tradeData['amount']}" 
              : "\$${widget.tradeData['amountFiat'] ?? widget.tradeData['amount']}",
          style: TextStyle(color: colors.accent, fontSize: 32, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _buildReceiptCard(String date, AzamanColors colors) {
    final otherParty = widget.isVendor 
        ? (widget.tradeData['userName'] ?? "Buyer") 
        : (widget.tradeData['vendorName'] ?? "Vendor");

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          _rowDetail("Order ID", widget.tradeData['tradeId']?.toString() ?? "N/A", colors),
          Divider(color: colors.divider, height: 25),
          _rowDetail("Date", date, colors),
          Divider(color: colors.divider, height: 25),
          _rowDetail(widget.isVendor ? "Buyer" : "Vendor", otherParty, colors),
          Divider(color: colors.divider, height: 25),
          _rowDetail("Payment Method", widget.tradeData['paymentMethod'] ?? "Bank Transfer", colors),
        ],
      ),
    );
  }

  Widget _rowDetail(String label, String value, AzamanColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 13)),
        Text(value, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildReviewSection(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "How was your trading experience?",
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isPositive = true);
                  },
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: _isPositive == true ? colors.success.withOpacity(0.2) : colors.background,
                      border: Border.all(color: _isPositive == true ? colors.success : colors.divider),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(HugeIconsSolid.thumbsUp, color: _isPositive == true ? colors.success : colors.textTertiary, size: 18),
                        const SizedBox(width: 8),
                        Text("Positive", style: TextStyle(color: _isPositive == true ? colors.success : colors.textTertiary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isPositive = false);
                  },
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: _isPositive == false ? colors.danger.withOpacity(0.2) : colors.background,
                      border: Border.all(color: _isPositive == false ? colors.danger : colors.divider),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(HugeIconsSolid.thumbsDown, color: _isPositive == false ? colors.danger : colors.textTertiary, size: 18),
                        const SizedBox(width: 8),
                        Text("Negative", style: TextStyle(color: _isPositive == false ? colors.danger : colors.textTertiary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isPositive != null) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _commentController,
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Leave a comment (Optional)",
                hintStyle: TextStyle(color: colors.textTertiary),
                filled: true,
                fillColor: colors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSubmitting ? null : _submitReview,
                child: _isSubmitting 
                    ? SizedBox(
                        height: 15,
                        width: 15,
                        child: CircularProgressIndicator(
                          color: colors.isDark ? Colors.black : Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        "Submit Review",
                        style: TextStyle(
                          color: colors.isDark ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            )
          ]
        ],
      ),
    );
  }

  Widget _buildThankYouCard(AzamanColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.success.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.success.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(HugeIconsSolid.favourite, color: colors.success, size: 30),
          const SizedBox(height: 10),
          Text(
            "Feedback Submitted",
            style: TextStyle(color: colors.success, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 5),
          Text(
            "Your review helps keep the Azaman community safe.",
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadReceiptButton(AzamanColors colors) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _isDownloadingReceipt ? null : _handleDownloadReceipt,
        icon: _isDownloadingReceipt
            ? SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  color: colors.accent,
                  strokeWidth: 2,
                ),
              )
            : Icon(HugeIconsSolid.download01, color: colors.accent, size: 20),
        label: Text(
          _isDownloadingReceipt ? 'Downloading...' : 'Download Receipt',
          style: TextStyle(
            color: colors.accent,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.accent.withOpacity(0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDownloadReceipt() async {
    final colors = ref.read(themeProvider).colors;
    final tradeId = widget.tradeData['tradeId']?.toString().replaceAll('#', '') ?? '';
    if (tradeId.isEmpty) return;

    setState(() => _isDownloadingReceipt = true);

    try {
      await ReceiptService.downloadTradeReceipt(tradeId);
      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Receipt downloaded successfully'),
            backgroundColor: colors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: colors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingReceipt = false);
    }
  }

  // ── Trade status timeline (P2P Premium Sprint, 2026-06-21) ─────────────────
  Widget _statusTimeline(AzamanColors colors) {
    final data = widget.tradeData;
    final steps = [
      _TimelineStep(
          label: 'Trade Opened',
          done: true,
          time: data['createdAt']?.toString()),
      _TimelineStep(
          label: 'Payment Sent',
          done: (data['isPaid'] ?? false) as bool,
          time: data['paidAt']?.toString()),
      _TimelineStep(
          label: 'Payment Confirmed',
          done: (data['isCompleted'] ?? false) as bool,
          time: data['completedAt']?.toString()),
      _TimelineStep(
          label: 'Released to Wallet',
          done: (data['isCompleted'] ?? false) as bool,
          time: data['releasedAt']?.toString()),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRADE TIMELINE',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < steps.length; i++) ...[
            _timelineRow(steps[i],
                isLast: i == steps.length - 1, colors: colors),
          ],
        ],
      ),
    );
  }

  Widget _timelineRow(_TimelineStep step,
      {required bool isLast, required AzamanColors colors}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: dot + connector line
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: step.done ? colors.success : colors.softSurface,
                    border: Border.all(
                      color: step.done ? colors.success : colors.divider,
                      width: 2,
                    ),
                  ),
                  child: step.done
                      ? const Icon(Icons.check, size: 10, color: Colors.white)
                      : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: step.done
                          ? colors.success.withValues(alpha: 0.4)
                          : colors.divider,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right: label + time
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      color:
                          step.done ? colors.textPrimary : colors.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (step.time != null && step.time!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(step.time!),
                      style:
                          TextStyle(color: colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}  $h:$m';
  }

  Widget _buildBottomBar(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            // Pop all the way back to the Dashboard
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: Text(
            "Back to Home",
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ),
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final bool done;
  final String? time;
  const _TimelineStep({required this.label, required this.done, this.time});
}

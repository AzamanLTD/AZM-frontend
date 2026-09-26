// lib/widgets/withdrawal_progress_sheet.dart
//
// =============================================================================
// AZAMAN V2 — WITHDRAWAL PROGRESS SHEET (r42 integration wave)
//
// Opens the moment a withdrawal is ACCEPTED (HTTP 202/200) with the
// reference the backend returned in the same response — the UI starts from
// the authoritative identity, never an invented client-side guess.
//
// Two modes, matching the two withdrawal surfaces:
//
//   .fiat({ reference })     → GET /api/withdraw/status/:reference
//                              (canonical fiat flow; also subscribes to
//                              `withdrawal_progress` / `withdrawal_settled`
//                              socket events for live updates, with polling
//                              as the missed-event fallback)
//   .wallet({ withdrawalId }) → GET /api/wallet/withdraw/status/:id
//                              (saved-payout queue; worker-driven, polled)
//
// Both resolve the row by its durable identity (reference / primary key) —
// the backend never correlates by amount or timestamp, and neither does
// this sheet.
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/providers/theme_provider.dart';

enum _Source { fiat, wallet }

enum _Stage { pending, processing, completed, failed, review }

class WithdrawalProgressSheet extends ConsumerStatefulWidget {
  const WithdrawalProgressSheet._({
    super.key,
    required this.source,
    this.reference,
    this.withdrawalId,
  });

  /// Canonical fiat withdrawal — tracked by its top-level reference.
  const WithdrawalProgressSheet.fiat({super.key, required this.reference})
      : source = _Source.fiat,
        withdrawalId = null;

  /// Saved-payout queue withdrawal — tracked by its numeric id.
  const WithdrawalProgressSheet.wallet({super.key, required this.withdrawalId})
      : source = _Source.wallet,
        reference = null;

  final _Source source;
  final String? reference;
  final int? withdrawalId;

  /// Same modal style the saved-payout sheets use.
  static Future<void> show(BuildContext context, Widget sheet) {
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.75;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: sheet,
        );
      },
    );
  }

  @override
  ConsumerState<WithdrawalProgressSheet> createState() =>
      _WithdrawalProgressSheetState();
}

class _WithdrawalProgressSheetState
    extends ConsumerState<WithdrawalProgressSheet> {
  Timer? _pollTimer;
  bool _settled = false;
  bool _firstFetch = true;

  // The observable state the backend reports.
  String _status = 'PENDING';
  _Stage _stage = _Stage.pending;
  String _label = 'Transfer requested…';
  int _pct = 20;

  // Context extras surfaced when the status endpoint provides them.
  String? _destination;
  double? _amount;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Poll every 5 s — the socket events are the fast path, but a dropped
    // socket (Moolre down / network blip) must never strand a stuck UI.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());

    if (widget.source == _Source.fiat) {
      SocketService.instance.onWithdrawalProgress(_onSocketEvent);
      SocketService.instance.onWithdrawalSettled(_onSocketEvent);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (widget.source == _Source.fiat) {
      // Release the singleton callbacks so a later sheet can subscribe.
      SocketService.instance.removeWithdrawalListeners();
    }
    super.dispose();
  }

  void _onSocketEvent(Map<String, dynamic> data) {
    if (!mounted || widget.source != _Source.fiat) return;
    if (data['reference'] != widget.reference) return;
    _applyServerState(
      status: data['status']?.toString(),
      stage: data['stage']?.toString(),
      label: data['label']?.toString(),
      pct: data['pct'] is num ? (data['pct'] as num).toInt() : null,
    );
  }

  Future<void> _refresh() async {
    if (_settled || !mounted) return;
    try {
      if (widget.source == _Source.fiat) {
        final response = await apiClient.get(
            '/withdraw/status/${Uri.encodeComponent(widget.reference!)}');
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          if (body['success'] == true) {
            if (body['recipient'] != null) {
              _destination = body['recipient'].toString();
            }
            final rawAmount = body['amountUsdc'];
            if (rawAmount is num) _amount = rawAmount.toDouble();
            _applyServerState(
              status: body['status']?.toString(),
              stage: body['stage']?.toString(),
              label: body['label']?.toString(),
              pct: body['pct'] is num ? (body['pct'] as num).toInt() : null,
            );
          }
        }
        // 404/5xx: transient or foreign — keep polling; the user can
        // always dismiss to the manual surface.
      } else {
        final response =
            await apiClient.get('/wallet/withdraw/status/${widget.withdrawalId}');
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          if (body['success'] == true) {
            final w = body['withdrawal'] as Map<String, dynamic>;
            if (w['destination'] != null) {
              _destination = w['destination'].toString();
            }
            final rawAmount = w['amount'];
            if (rawAmount is num) _amount = rawAmount.toDouble();
            _applyServerState(status: w['status']?.toString());
          }
        }
      }
    } catch (_) {
      // Network blip — the next tick retries. Never a dead-end error state.
    } finally {
      if (mounted && _firstFetch) setState(() => _firstFetch = false);
    }
  }

  void _applyServerState({
    String? status,
    String? stage,
    String? label,
    int? pct,
  }) {
    if (!mounted) return;
    setState(() {
      if (status != null) _status = status;

      switch (_status.toUpperCase()) {
        case 'COMPLETED':
          _stage = _Stage.completed;
          _label = label ?? 'Money sent successfully!';
          _pct = pct ?? 100;
          _settle();
          break;
        case 'FAILED':
          _stage = _Stage.failed;
          // The backend's definitive-rejection contract: a FAILED fiat
          // withdrawal was already durably reversed (refund issued).
          // Never tell the user the money vanished.
          _label = label ?? 'Refund issued — your balance was restored.';
          _pct = pct ?? 0;
          _settle();
          break;
        case 'REJECTED':
        case 'NEEDS_MANUAL_REVIEW':
          _stage = _Stage.review;
          _label = label ?? 'Held for review — our team will contact you.';
          _pct = pct ?? 0;
          _settle();
          break;
        case 'PROCESSING':
          _stage = _Stage.processing;
          _label = label ?? 'Transfer in progress…';
          _pct = pct ?? 40;
          break;
        case 'PENDING':
        default:
          _stage = _Stage.pending;
          _label = label ?? 'Transfer requested…';
          _pct = pct ?? 20;
          break;
      }
    });
  }

  void _settle() {
    _settled = true;
    _pollTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    final (icon, iconColor) = switch (_stage) {
      _Stage.completed => (Icons.check_circle_rounded, colors.success),
      _Stage.failed => (Icons.replay_rounded, colors.warning),
      _Stage.review => (Icons.schedule_rounded, colors.warning),
      _ => (Icons.downloading_rounded, colors.accent),
    };

    final done = _stage == _Stage.completed ||
        _stage == _Stage.failed ||
        _stage == _Stage.review;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Icon(icon, size: 56, color: iconColor),
          const SizedBox(height: 12),
          Text(
            'Withdrawal in progress',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _label,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          if (_amount != null) ...[
            const SizedBox(height: 4),
            Text(
              '${_amount!.toStringAsFixed(2)} USDC'
              '${_destination != null ? "  →  $_destination" : ""}',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
          if (widget.source == _Source.fiat) ...[
            const SizedBox(height: 14),
            Text(
              'Reference: ${widget.reference}',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          if (!done) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: (_pct / 100 - 0.15).clamp(0.0, 1.0), end: (_pct / 100).clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: colors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_status · $_pct%',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colors.background,
              ),
              onPressed: () {
                _pollTimer?.cancel();
                Navigator.of(context).pop();
              },
              child: Text(done ? 'Done' : 'Track it in history'),
            ),
          ),
        ],
      ),
    );
  }
}

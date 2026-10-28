import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:go_router/go_router.dart' show GoRouterHelper;

enum _RequestDirection { incoming, outgoing }

/// First-class requests inbox/outbox. It is independent of chat and uses only
/// the standalone /payment-requests API contract (AZM-backend PR #332):
///
///   • GET  /payment-requests?direction=INCOMING|OUTGOING — list rows carry
///     NO token material and NO share URL (the server only issues a LINK's
///     shareUrl inside the create response).
///   • POST /payment-requests/:id/cancel — requester-only, idempotent,
///     single-winner on PENDING.
///   • POST /payment-requests/:id/decline — recipient-only, DIRECT only,
///     idempotent, single-winner on PENDING.
///
/// There is NO pay/accept-and-pay endpoint and NO PAID status: the backend
/// has no GHS settlement rail yet (a separate, tracked dependency). This
/// screen therefore never renders a paid state or a payment action. Tapping
/// a row opens a detail sheet built ONLY from the list DTO — no token is
/// invented and no share URL is reconstructed.
class PaymentRequestsScreen extends ConsumerStatefulWidget {
  const PaymentRequestsScreen({super.key});

  @override
  ConsumerState<PaymentRequestsScreen> createState() =>
      _PaymentRequestsScreenState();
}

class _PaymentRequestsScreenState extends ConsumerState<PaymentRequestsScreen> {
  _RequestDirection _direction = _RequestDirection.incoming;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = const [];

  /// Per-request retry handles for the idempotent terminal operations. The
  /// r42 client operation-instance model: a retry of the SAME cancel/decline
  /// must reuse the SAME durable instance (and therefore the same
  /// Idempotency-Key); acting on a different request starts a new instance.
  final Map<String, FinancialOperationRef> _operations = {};

  static const _terminalStatuses = {'CANCELLED', 'DECLINED', 'EXPIRED'};

  FinancialOperationRef _operationRef(String requestId, String action) =>
      _operations.putIfAbsent('$action:$requestId', FinancialOperationRef.new);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final direction = _direction == _RequestDirection.incoming
          ? 'INCOMING'
          : 'OUTGOING';
      final response = await ref
          .read(apiClientProvider)
          .get('/payment-requests?direction=$direction');
      final decoded = jsonDecode(response.body);
      final root = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          message: (root['message'] ?? 'Could not load payment requests.')
              .toString(),
          statusCode: response.statusCode,
          code: root['code']?.toString(),
        );
      }
      final data = root['data'] is Map<String, dynamic>
          ? root['data'] as Map<String, dynamic>
          : root;
      final raw = data['requests'];
      final requests = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Payment requests are unavailable. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _selectDirection(_RequestDirection direction) async {
    if (_direction == direction) return;
    AzamanHaptics.toggle();
    setState(() {
      _direction = direction;
      _requests = const [];
    });
    await _load();
  }

  String _person(Map<String, dynamic> request) {
    final person = _direction == _RequestDirection.incoming
        ? request['requester']
        : request['recipient'];
    if (person is Map) {
      final value =
          person['displayName'] ??
          person['name'] ??
          person['username'] ??
          person['azamanId'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    final value = _direction == _RequestDirection.incoming
        ? request['requesterDisplayName']
        : request['recipientDisplayName'];
    return value?.toString().trim().isNotEmpty == true
        ? value.toString()
        : _direction == _RequestDirection.incoming
        ? 'Azaman contact'
        : 'Anyone with the link';
  }

  String _amount(Map<String, dynamic> request) {
    final amount = request['amount']?.toString();
    final currency = request['currency']?.toString().toUpperCase() ?? 'GHS';
    if (amount == null || amount.isEmpty) return 'Amount unavailable';
    final prefix = currency == 'GHS'
        ? 'GH₵ '
        : currency == 'USDC'
        ? ''
        : '$currency ';
    return prefix + amount + (currency == 'USDC' ? ' USDC' : '');
  }

  bool get _viewerIsRequester => _direction == _RequestDirection.outgoing;

  /// Idempotent terminal transition (cancel for the requester, decline for
  /// the recipient of a DIRECT request). Operation identity is the durable
  /// client instance: a retry of the same action reuses the same key, so a
  /// 409/timeout never double-fires.
  Future<String?> _resolve({
    required Map<String, dynamic> request,
    required String action,
    required void Function(String message) onMessage,
  }) async {
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      onMessage('This request has no server identity. Refresh and try again.');
      return null;
    }
    final ref = _operationRef(requestId, action);
    final outcome = await _resolveRequest(
      action: action,
      id: requestId,
      opRef: ref,
    );
    if (outcome == null) return null;
    final updated = outcome;
    if (!mounted) return null;
    final statusCode = updated['statusCode'] as int;
    final root = updated['body'] is Map<String, dynamic>
        ? updated['body'] as Map<String, dynamic>
        : <String, dynamic>{};
    final message = (root['message'] ?? 'The request could not be updated.')
        .toString();
    if (statusCode < 200 || statusCode >= 300) {
      // Unknown outcomes (5xx, network, 401, 429) keep the operation ref
      // armed: the SAME retry reuses the SAME idempotency key, so it can
      // never double-fire. Definitive 4xx conflicts converge honestly on
      // the server-reported committed state.
      final unknown =
          statusCode == 0 ||
          statusCode >= 500 ||
          statusCode == 401 ||
          statusCode == 429;
      onMessage(
        unknown
            ? 'We could not confirm whether the request was updated. '
                  'Retrying the same action is safe.'
            : message,
      );
      await _load();
      return null;
    }
    final data = root['data'] is Map<String, dynamic>
        ? root['data'] as Map<String, dynamic>
        : root;
    final candidate = data['request'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(data['request'] as Map)
        : null;
    _operations.remove('$action:$requestId');
    setState(() {
      final index = _requests.indexWhere(
        (row) => row['id']?.toString() == requestId,
      );
      if (index >= 0 && candidate != null) {
        _requests[index] = candidate;
      }
    });
    return message;
  }

  Future<Map<String, dynamic>?> _resolveRequest({
    required String action,
    required String id,
    required FinancialOperationRef opRef,
  }) async {
    try {
      final response = await ref
          .read(apiClientProvider)
          .postFinancial(
            '/payment-requests/$id/$action',
            {},
            operationType: 'payment.request.$action',
            ref: opRef,
          );
      return {
        'statusCode': response.statusCode,
        'body': jsonDecode(response.body),
      };
    } on ApiException catch (error) {
      return {'statusCode': error.statusCode, 'body': <String, dynamic>{}};
    } catch (_) {
      // Network/timeout: outcome genuinely unknown. The ref stays armed —
      // the SAME retry reuses the SAME idempotency key.
      return {'statusCode': 0, 'body': <String, dynamic>{}};
    }
  }

  /// Detail surface built ONLY from the list DTO. The list carries no token
  /// material, so LINK requests honestly explain that the share link was
  /// issued at creation and — if lost — the documented recovery is to cancel
  /// and create a replacement. Nothing is fabricated or stored here.
  Future<void> _openDetail(Map<String, dynamic> request) async {
    AzamanHaptics.navigation();
    final colors = ref.read(themeProvider).colors;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _RequestDetailSheet(
        key: const ValueKey('payment-request-detail'),
        request: Map<String, dynamic>.from(request),
        viewerIsRequester: _viewerIsRequester,
        colors: colors,
        onResolve: ({required String action, required onMessage}) =>
            _resolve(request: request, action: action, onMessage: onMessage),
      ),
    );
    // The sheet may have changed the row (cancel/decline); the in-place
    // update already happened, nothing further to reload here.
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final incoming = _direction == _RequestDirection.incoming;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        // bottom: true — the list and its last row must clear the
        // home-indicator inset; nothing may rest under it.
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close requests',
                    onPressed: () {
                      AzamanHaptics.navigation();
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AzRoutes.shell);
                      }
                    },
                    icon: Icon(Icons.close, color: colors.textPrimary),
                  ),
                  const SizedBox(width: AzSpace.sm),
                  Expanded(
                    child: Text(
                      'Requests',
                      style: AzText.titleXl.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh requests',
                    onPressed: _load,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AzSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: _DirectionPill(
                      label: 'Incoming',
                      selected: incoming,
                      onTap: () => _selectDirection(_RequestDirection.incoming),
                    ),
                  ),
                  const SizedBox(width: AzSpace.sm),
                  Expanded(
                    child: _DirectionPill(
                      label: 'Sent',
                      selected: !incoming,
                      onTap: () => _selectDirection(_RequestDirection.outgoing),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AzSpace.md),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 160),
                          Center(child: CircularProgressIndicator()),
                        ],
                      )
                    : _error != null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AzSpace.xl),
                        children: [
                          const SizedBox(height: 100),
                          Icon(
                            Icons.cloud_off_rounded,
                            color: colors.textTertiary,
                            size: 42,
                          ),
                          const SizedBox(height: AzSpace.md),
                          Text(
                            _error!,
                            style: AzText.body.copyWith(
                              color: colors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AzSpace.md),
                          Center(
                            child: TextButton(
                              onPressed: _load,
                              child: const Text('Try again'),
                            ),
                          ),
                        ],
                      )
                    : _requests.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AzSpace.xl),
                        children: [
                          const SizedBox(height: 100),
                          Icon(
                            incoming
                                ? Icons.inbox_rounded
                                : Icons.outbox_rounded,
                            color: colors.textTertiary,
                            size: 46,
                          ),
                          const SizedBox(height: AzSpace.md),
                          Text(
                            incoming
                                ? 'No incoming requests'
                                : 'No requests sent yet',
                            style: AzText.title.copyWith(
                              color: colors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AzSpace.sm),
                          Text(
                            incoming
                                ? 'Requests from Azaman contacts will appear here, outside your chats.'
                                : 'Requests you create will be tracked here independently of chat.',
                            style: AzText.body.copyWith(
                              color: colors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : ListView.separated(
                        key: const ValueKey('payment-requests-list'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AzSpace.lg,
                          0,
                          AzSpace.lg,
                          24,
                        ),
                        itemCount: _requests.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AzSpace.sm),
                        itemBuilder: (context, index) {
                          final request = _requests[index];
                          final status =
                              (request['status']?.toString() ?? 'UNKNOWN')
                                  .replaceAll('_', ' ');
                          final terminal = _terminalStatuses.contains(
                            (request['status']?.toString() ?? '').toUpperCase(),
                          );
                          return Material(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _openDetail(request),
                              child: Padding(
                                padding: const EdgeInsets.all(AzSpace.lg),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: terminal
                                            ? colors.softSurface
                                            : colors.isDark
                                            ? const Color(0xFF254B39)
                                            : const Color(0xFFC9DDCF),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        terminal
                                            ? Icons.receipt_long_rounded
                                            : incoming
                                            ? Icons.south_west_rounded
                                            : Icons.north_east_rounded,
                                        color: terminal
                                            ? colors.textSecondary
                                            : colors.isDark
                                            ? const Color(0xFFD9EBDD)
                                            : const Color(0xFF254B39),
                                      ),
                                    ),
                                    const SizedBox(width: AzSpace.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _person(request),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AzText.body.copyWith(
                                              color: colors.textPrimary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            status,
                                            style: AzText.bodyS.copyWith(
                                              color: colors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: AzSpace.sm),
                                    Text(
                                      _amount(request),
                                      textAlign: TextAlign.end,
                                      style: AzText.body.copyWith(
                                        color: colors.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Request detail, built strictly from the actual list DTO. The requester
/// can cancel a pending request; the recipient can decline a pending
/// DIRECT request. LINK requests never fabricate a share URL — the sheet
/// states the documented recovery (cancel + create a replacement).
class _RequestDetailSheet extends StatefulWidget {
  const _RequestDetailSheet({
    super.key,
    required this.request,
    required this.viewerIsRequester,
    required this.colors,
    required this.onResolve,
  });

  final Map<String, dynamic> request;
  final bool viewerIsRequester;
  final AzamanColors colors;

  /// Runs the idempotent terminal operation. Returns a success message on
  /// 2xx (the row was already updated in place), or null after reporting an
  /// honest failure message via [onMessage].
  final Future<String?> Function({
    required String action,
    required void Function(String message) onMessage,
  })
  onResolve;

  @override
  State<_RequestDetailSheet> createState() => _RequestDetailSheetState();
}

class _RequestDetailSheetState extends State<_RequestDetailSheet> {
  String? _message;
  bool _working = false;

  bool get _pending =>
      (widget.request['status']?.toString() ?? '').toUpperCase() == 'PENDING';

  bool get _isDirect =>
      (widget.request['mode']?.toString() ?? '').toUpperCase() == 'DIRECT';

  String get _displayName {
    final who = widget.viewerIsRequester
        ? widget.request['recipient']
        : widget.request['requester'];
    if (who is Map) {
      final value = who['displayName'] ?? who['username'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    final fallback = widget.viewerIsRequester
        ? widget.request['recipientDisplayName']
        : widget.request['requesterDisplayName'];
    if (fallback?.toString().trim().isNotEmpty == true)
      return fallback.toString();
    return widget.viewerIsRequester && !_isDirect
        ? 'Anyone with the link'
        : 'Azaman contact';
  }

  Future<void> _run(String action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    final result = await widget.onResolve(
      action: action,
      onMessage: (message) {
        if (mounted) {
          setState(() => _message = message);
        }
      },
    );
    if (!mounted) return;
    if (result != null) {
      AzamanHaptics.confirm();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(result)));
      return;
    }
    setState(() => _working = false);
  }

  String? _date(String key) {
    final raw = widget.request[key];
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    return DateFormat('d MMM y, HH:mm').format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final amount = widget.request['amount']?.toString();
    final status = (widget.request['status']?.toString() ?? 'UNKNOWN')
        .replaceAll('_', ' ');
    final canCancel = widget.viewerIsRequester && _pending;
    final canDecline = !widget.viewerIsRequester && _pending && _isDirect;
    final missingLink = widget.viewerIsRequester && !_isDirect && _pending;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AzSpace.lg,
            AzSpace.lg,
            AzSpace.lg,
            AzSpace.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.viewerIsRequester
                          ? 'Request to $_displayName'
                          : 'Request from $_displayName',
                      style: AzText.title.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: AzSpace.sm),
                  Text(
                    amount == null ? '' : 'GH₵ $amount',
                    style: AzText.title.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AzSpace.md),
              Container(
                padding: const EdgeInsets.all(AzSpace.md),
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    _DetailRow(label: 'Status', value: status),
                    _DetailRow(
                      label: 'Type',
                      value: _isDirect
                          ? 'Direct request'
                          : 'Shareable link request',
                    ),
                    if (_date('createdAt') != null)
                      _DetailRow(label: 'Created', value: _date('createdAt')!),
                    if (_date('expiresAt') != null)
                      _DetailRow(label: 'Expires', value: _date('expiresAt')!),
                    if (_date('resolvedAt') != null)
                      _DetailRow(
                        label: 'Resolved',
                        value: _date('resolvedAt')!,
                      ),
                    _DetailRow(
                      label: 'Request ID',
                      value: widget.request['id']?.toString() ?? 'Unavailable',
                    ),
                  ],
                ),
              ),
              if (missingLink) ...[
                const SizedBox(height: AzSpace.md),
                Text(
                  'The share link for this request was shown when it was '
                  'created and is not stored anywhere. If you lost it, cancel '
                  'this request and create a replacement.',
                  style: AzText.bodyS.copyWith(color: colors.textSecondary),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: AzSpace.md),
                Text(
                  _message!,
                  style: AzText.bodyS.copyWith(color: colors.danger),
                ),
              ],
              if (canCancel || canDecline) ...[
                const SizedBox(height: AzSpace.md),
                Row(
                  children: [
                    if (canCancel)
                      Expanded(
                        child: _DetailActionButton(
                          key: const ValueKey('payment-request-cancel'),
                          label: _working ? 'Cancelling…' : 'Cancel request',
                          danger: true,
                          enabled: !_working,
                          onPressed: () => _run('cancel'),
                          colors: colors,
                        ),
                      ),
                    if (canDecline)
                      Expanded(
                        child: _DetailActionButton(
                          key: const ValueKey('payment-request-decline'),
                          label: _working ? 'Declining…' : 'Decline request',
                          danger: true,
                          enabled: !_working,
                          onPressed: () => _run('decline'),
                          colors: colors,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  const _DetailActionButton({
    super.key,
    required this.label,
    required this.danger,
    required this.enabled,
    required this.onPressed,
    required this.colors,
  });

  final String label;
  final bool danger;
  final bool enabled;
  final VoidCallback onPressed;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: AzSpace.xs),
          decoration: BoxDecoration(
            color: enabled
                ? colors.danger.withValues(alpha: 0.12)
                : colors.softSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? colors.danger.withValues(alpha: 0.4)
                  : colors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AzText.body.copyWith(
              color: enabled ? colors.danger : colors.textTertiary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: AzText.bodyS.copyWith(
                color: colors.colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          const SizedBox(width: AzSpace.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AzText.body.copyWith(
                color: colors.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionPill extends StatelessWidget {
  const _DirectionPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label payment requests',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.45)
                  : theme.colorScheme.outline.withValues(alpha: 0.15),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AzText.body.copyWith(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.62),
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

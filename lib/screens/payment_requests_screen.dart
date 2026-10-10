import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

enum _RequestDirection { incoming, outgoing }

/// First-class requests inbox/outbox. It is independent of chat and uses only
/// the standalone /payment-requests API contract (added in the backend follow-up).
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
      final direction =
          _direction == _RequestDirection.incoming ? 'INCOMING' : 'OUTGOING';
      final response = await apiClient.get('/payment-requests?direction=$direction');
      final decoded = jsonDecode(response.body);
      final root = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          message: (root['message'] ?? 'Could not load payment requests.').toString(),
          statusCode: response.statusCode,
          code: root['code']?.toString(),
        );
      }
      final data = root['data'] is Map<String, dynamic>
          ? root['data'] as Map<String, dynamic>
          : root;
      final raw = data['requests'];
      final requests = raw is List
          ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
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
      final value = person['displayName'] ?? person['name'] ??
          person['username'] ?? person['azamanId'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    final value = _direction == _RequestDirection.incoming
        ? request['requesterDisplayName']
        : request['recipientDisplayName'];
    return value?.toString().trim().isNotEmpty == true
        ? value.toString()
        : 'Azaman contact';
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

  void _openRequest(Map<String, dynamic> request) {
    final token = (request['publicToken'] ??
            request['shareToken'] ??
            request['token'] ??
            '')
        .toString();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This request has no detail link yet.')),
      );
      return;
    }
    AzamanHaptics.navigation();
    context.push(AzRoutes.paymentRequestLink(token));
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final incoming = _direction == _RequestDirection.incoming;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
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
                        context.go('/');
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
                    icon: Icon(Icons.refresh_rounded, color: colors.textPrimary),
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
                              Icon(Icons.cloud_off_rounded,
                                  color: colors.textTertiary, size: 42),
                              const SizedBox(height: AzSpace.md),
                              Text(_error!,
                                  style: AzText.body.copyWith(
                                      color: colors.textSecondary),
                                  textAlign: TextAlign.center),
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
                                    incoming ? Icons.inbox_rounded : Icons.outbox_rounded,
                                    color: colors.textTertiary,
                                    size: 46,
                                  ),
                                  const SizedBox(height: AzSpace.md),
                                  Text(
                                    incoming
                                        ? 'No incoming requests'
                                        : 'No requests sent yet',
                                    style: AzText.title.copyWith(
                                        color: colors.textPrimary),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: AzSpace.sm),
                                  Text(
                                    incoming
                                        ? 'Requests from Azaman contacts will appear here, outside your chats.'
                                        : 'Requests you create will be tracked here independently of chat.',
                                    style: AzText.body.copyWith(
                                        color: colors.textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                    AzSpace.lg, 0, AzSpace.lg, 24),
                                itemCount: _requests.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: AzSpace.sm),
                                itemBuilder: (context, index) {
                                  final request = _requests[index];
                                  final status = (request['status']?.toString() ??
                                          'UNKNOWN')
                                      .replaceAll('_', ' ');
                                  final terminal = const {
                                    'PAID',
                                    'DECLINED',
                                    'CANCELLED',
                                    'EXPIRED',
                                    'REFUSED',
                                  }.contains(status.toUpperCase());
                                  return Material(
                                    color: colors.card,
                                    borderRadius: BorderRadius.circular(20),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () => _openRequest(request),
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

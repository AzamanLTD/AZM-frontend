import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Public, share-link landing for a standalone payment request.
///
/// The public details endpoint is a backend dependency. This screen never
/// marks a request paid or attempts a transfer itself; settlement belongs to
/// the authenticated financial API and will be enabled once that contract is
/// implemented and reviewed.
class PaymentRequestLandingScreen extends ConsumerStatefulWidget {
  const PaymentRequestLandingScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<PaymentRequestLandingScreen> createState() =>
      _PaymentRequestLandingScreenState();
}

class _PaymentRequestLandingScreenState
    extends ConsumerState<PaymentRequestLandingScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _request;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant PaymentRequestLandingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _request = null;
    });
    try {
      final token = Uri.encodeComponent(widget.token);
      final response = await ref.read(apiClientProvider).get(
        '/payment-requests/public/$token',
        requireAuth: false,
      );
      final decoded = jsonDecode(response.body);
      final root = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          message: (root['message'] ??
                  'This payment request could not be found or is no longer available.')
              .toString(),
          statusCode: response.statusCode,
          code: root['code']?.toString(),
        );
      }
      final data = root['data'] is Map<String, dynamic>
          ? root['data'] as Map<String, dynamic>
          : root;
      final candidate = data['request'] is Map<String, dynamic>
          ? data['request'] as Map<String, dynamic>
          : data;
      if (!mounted) return;
      setState(() {
        _request = Map<String, dynamic>.from(candidate);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'This payment request is unavailable. Try opening the link again.';
        _loading = false;
      });
    }
  }

  String _requester(Map<String, dynamic> request) {
    final who = request['requester'];
    if (who is Map) {
      final name =
          who['displayName'] ?? who['name'] ?? who['username'] ?? who['azamanId'];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString();
      }
    }
    final name = request['requesterDisplayName'] ??
        request['requesterName'] ??
        request['fromName'];
    return name?.toString().trim().isNotEmpty == true
        ? name.toString()
        : 'An Azaman user';
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

  bool _isActive(Map<String, dynamic> request) {
    final status = request['status']?.toString().toUpperCase();
    return status == 'PENDING' || status == 'OPEN' || status == 'ACTIVE';
  }

  void _copyLink() {
    final link = (_request?['shareUrl'] ?? _request?['requestUrl'] ?? '')
        .toString()
        .trim();
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The server did not provide a shareable link for this request.'),
        ),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: link));
    AzamanHaptics.confirm();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Request link copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final request = _request;
    final active = request != null && _isActive(request);

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AzSpace.lg,
            AzSpace.md,
            AzSpace.lg,
            AzSpace.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Close request',
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
                      'Payment request',
                      style: AzText.title.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy request link',
                    onPressed: _copyLink,
                    icon: Icon(Icons.link_rounded, color: colors.textPrimary),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : _error != null
                          ? _UnavailableRequest(
                              message: _error!,
                              onRetry: _load,
                            )
                          : request == null
                              ? _UnavailableRequest(
                                  message: 'This request is unavailable.',
                                  onRetry: _load,
                                )
                              : SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const SizedBox(height: AzSpace.xl),
                                      Center(
                                        child: Container(
                                          width: 76,
                                          height: 76,
                                          decoration: BoxDecoration(
                                            color: active
                                                ? colors.isDark
                                                    ? const Color(0xFF254B39)
                                                    : const Color(0xFFC9DDCF)
                                                : colors.softSurface,
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            active
                                                ? Icons.request_quote_rounded
                                                : Icons.receipt_long_rounded,
                                            size: 34,
                                            color: active
                                                ? colors.isDark
                                                    ? const Color(0xFFD9EBDD)
                                                    : const Color(0xFF254B39)
                                                : colors.textSecondary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: AzSpace.lg),
                                      Text(
                                        'Payment request from ${_requester(request)}',
                                        style: AzText.title.copyWith(
                                          color: colors.textPrimary,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: AzSpace.sm),
                                      Text(
                                        _amount(request),
                                        style: AzText.display.copyWith(
                                          color: colors.textPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: AzSpace.md),
                                      Container(
                                        padding: const EdgeInsets.all(
                                          AzSpace.lg,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.card,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: colors.border,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            _RequestDetailRow(
                                              label: 'Status',
                                              value: (request['status']
                                                          ?.toString() ??
                                                      'UNKNOWN')
                                                  .replaceAll('_', ' '),
                                            ),
                                            if (request['description'] != null &&
                                                request['description']
                                                    .toString()
                                                    .trim()
                                                    .isNotEmpty) ...[
                                              const SizedBox(
                                                height: AzSpace.md,
                                              ),
                                              _RequestDetailRow(
                                                label: 'Note',
                                                value: request['description']
                                                    .toString(),
                                              ),
                                            ],
                                            const SizedBox(
                                              height: AzSpace.md,
                                            ),
                                            _RequestDetailRow(
                                              label: 'Request ID',
                                              value: (request['publicId'] ??
                                                      request['requestId'] ??
                                                      request['id'] ??
                                                      'Unavailable')
                                                  .toString(),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: AzSpace.lg),
                                      Text(
                                        active
                                            ? 'The request is still active. Payment is not initiated by opening this link; the secure payment action will be enabled with the standalone request API.'
                                            : 'This request is no longer active. Contact the requester if you need an updated request.',
                                        style: AzText.body.copyWith(
                                          color: colors.textSecondary,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: AzSpace.md),
                                      OutlinedButton.icon(
                                        onPressed: _copyLink,
                                        icon: const Icon(Icons.copy_rounded),
                                        label: const Text('Copy request link'),
                                      ),
                                    ],
                                  ),
                                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnavailableRequest extends StatelessWidget {
  const _UnavailableRequest({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.link_off_rounded,
            color: colors.colorScheme.onSurface.withValues(alpha: 0.5),
            size: 44),
        const SizedBox(height: AzSpace.md),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AzText.body.copyWith(color: colors.colorScheme.onSurface),
        ),
        const SizedBox(height: AzSpace.md),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

class _RequestDetailRow extends StatelessWidget {
  const _RequestDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context);
    return Row(
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
    );
  }
}

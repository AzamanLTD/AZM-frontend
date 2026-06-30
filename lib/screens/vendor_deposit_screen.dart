import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';


class VendorDepositScreen extends ConsumerStatefulWidget {
  const VendorDepositScreen({super.key});

  @override
  ConsumerState<VendorDepositScreen> createState() => _VendorDepositScreenState();
}

class _VendorDepositScreenState extends ConsumerState<VendorDepositScreen> {
  String _tatumPolygonAddress = '';
  double _availableBalance = 0.0;
  // Phase J (2026-05-25): renamed from _lockedBalance and rebound to the
  // V2 `escrowLockedBalance`. The dropped legacy column was always 0.0 so
  // the "locked in escrow" hint never appeared; it now does for vendors
  // with active trades.
  double _escrowLockedBalance = 0.0;
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchDepositData();
      _startPolling();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDepositData() async {
    try {
      final auth = ref.read(authProvider);
      final userId = auth.user?.id;
      if (userId == null) return;

      final response = await apiClient.get('/auth/me/$userId');

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _tatumPolygonAddress =
              data['tatumPolygonAddress']?.toString() ?? '';
          _availableBalance =
              double.tryParse(data['availableBalance']?.toString() ?? '0') ??
                  0.0;
          _escrowLockedBalance =
              double.tryParse(data['escrowLockedBalance']?.toString() ?? '0') ??
                  0.0;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('VendorDeposit fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchDepositData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Deposit USDT (Polygon)',
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : RefreshIndicator(
              onRefresh: _fetchDepositData,
              color: colors.accent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: colors.accent.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('AVAILABLE BALANCE',
                                  style: TextStyle(
                                      color: colors.textTertiary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5)),
                              Icon(Icons.shield_outlined,
                                  color: colors.accent.withOpacity(0.5),
                                  size: 18),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_availableBalance.toStringAsFixed(2)} USDT',
                            style: TextStyle(
                              color: colors.success,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_escrowLockedBalance > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${_escrowLockedBalance.toStringAsFixed(2)} USDT locked in escrow',
                              style: TextStyle(
                                  color: colors.textTertiary, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_tatumPolygonAddress.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: colors.warning.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: colors.warning.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: colors.warning, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No Polygon deposit address found. Contact support.',
                                style: TextStyle(
                                    color: colors.warning, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: colors.accent.withOpacity(0.3)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'DEPOSIT ADDRESS',
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: QrImageView(
                                data: _tatumPolygonAddress,
                                version: QrVersions.auto,
                                size: 200,
                                backgroundColor: Colors.white,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Colors.black,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.card,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: colors.divider),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _tatumPolygonAddress,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(Icons.copy_outlined,
                                        color: colors.accent, size: 20),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      Clipboard.setData(ClipboardData(
                                          text: _tatumPolygonAddress));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                              'Address copied to clipboard'),
                                          backgroundColor: colors.success,
                                          behavior:
                                              SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.warning.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: colors.warning.withOpacity(0.15)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                color: colors.warning, size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Send only USDT on the Polygon (MATIC) network to this address. '
                                'Sending other tokens or using a different network may result in loss of funds. '
                                'Balance refreshes automatically every 10 seconds.',
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: 11,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

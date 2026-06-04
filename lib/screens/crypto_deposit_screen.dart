// =============================================================================
// CRYPTO DEPOSIT SCREEN — Polygon USDC Deposit Address with QR Code
//
// Shows the user's unique Polygon USDC deposit address with:
//   - QR code for easy scanning
//   - Copy-to-clipboard button
//   - Network warning (Polygon only!)
//   - Address derivation on first load (from backend)
//   - Real-time deposit confirmation via socket
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

class CryptoDepositScreen extends ConsumerStatefulWidget {
  const CryptoDepositScreen({super.key});

  @override
  ConsumerState<CryptoDepositScreen> createState() => _CryptoDepositScreenState();
}

class _CryptoDepositScreenState extends ConsumerState<CryptoDepositScreen> {
  String? _address;
  bool _isLoading = true;
  String? _error;
  bool _isNew = false;

  @override
  void initState() {
    super.initState();
    _fetchDepositAddress();
  }

  Future<void> _fetchDepositAddress() async {
    try {
      final response = await apiClient.get('/wallet/deposit-address/polygon');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        setState(() {
          _address = data['address'];
          _isNew = data['isNew'] == true;
          _isLoading = false;
        });
      } else {
        final body = jsonDecode(response.body);
        setState(() {
          _error = body['message'] ?? 'Failed to get deposit address';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error: $e';
        _isLoading = false;
      });
    }
  }

  void _copyAddress() {
    if (_address == null) return;
    Clipboard.setData(ClipboardData(text: _address!));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Address copied to clipboard'),
        backgroundColor: ref.read(themeProvider).colors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Deposit USDC', style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: colors.textPrimary),
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _error != null
              ? _buildError(colors)
              : _buildContent(colors),
    );
  }

  Widget _buildError(AzamanColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: colors.danger),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary, fontSize: 14)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () { setState(() { _isLoading = true; _error = null; }); _fetchDepositAddress(); },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AzamanColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Network badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.accent.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hexagon_outlined, color: colors.accent, size: 18),
                const SizedBox(width: 8),
                Text('Polygon Network', style: TextStyle(color: colors.accent, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('USDC', style: TextStyle(color: colors.success, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // QR Code
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: colors.glow.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: QrImageView(
              data: _address ?? '',
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF1A1A2E)),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF1A1A2E)),
            ),
          ),

          const SizedBox(height: 24),

          // Address display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Deposit Address', style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  _address ?? '',
                  style: TextStyle(color: colors.textPrimary, fontSize: 13, fontFamily: 'monospace', height: 1.4),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _copyAddress,
                    icon: Icon(Icons.copy_rounded, size: 16, color: colors.accent),
                    label: Text('Copy Address', style: TextStyle(color: colors.accent, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.accent.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Warning card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.warning.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colors.warning, size: 20),
                    const SizedBox(width: 8),
                    Text('Important', style: TextStyle(color: colors.warning, fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                _warningRow(colors, 'Only send USDC on the Polygon network'),
                _warningRow(colors, 'Other tokens or networks will result in permanent loss'),
                _warningRow(colors, 'Minimum deposit: 1 USDC'),
                _warningRow(colors, 'Funds credited within 2-5 minutes after confirmation'),
              ],
            ),
          ),

          if (_isNew) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: colors.success, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your deposit address has been generated. It is permanently linked to your account.',
                      style: TextStyle(color: colors.success, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _warningRow(AzamanColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          Expanded(child: Text(text, style: TextStyle(color: colors.textSecondary, fontSize: 12))),
        ],
      ),
    );
  }
}

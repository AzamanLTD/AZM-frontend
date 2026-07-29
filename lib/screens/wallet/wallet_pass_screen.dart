// =============================================================================
// AZAMAN — Wallet Pass Screen (Phase 3)
//
// Generates Apple Wallet (.pkpass) and Google Wallet pass for:
//   • Loyalty stamp cards
//   • Savings vaults
//
// Shows a preview of the pass and provides "Add to Apple Wallet" /
// "Save to Google Wallet" buttons.
//
// Reference: Starbucks rewards card in Apple Wallet, Google Wallet save flow
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

// ── Screen ──────────────────────────────────────────────────────────────────

class WalletPassScreen extends ConsumerStatefulWidget {
  final String passType; // 'loyalty' | 'vault'
  final String itemId; // cardId or vaultId
  final String title;
  final String subtitle;

  const WalletPassScreen({
    super.key,
    required this.passType,
    required this.itemId,
    this.title = '',
    this.subtitle = '',
  });

  @override
  ConsumerState<WalletPassScreen> createState() => _WalletPassScreenState();
}

class _WalletPassScreenState extends ConsumerState<WalletPassScreen> {
  bool _busy = false;
  Map<String, dynamic>? _passData;
  String? _saveUrl;
  String? _platform;

  @override
  void initState() {
    super.initState();
    _generatePass(Platform.isIOS ? 'apple' : 'google');
  }

  Future<void> _generatePass(String platform) async {
    setState(() => _busy = true);
    try {
      final endpoint = widget.passType == 'loyalty'
          ? '/wallet-pass/loyalty/${widget.itemId}'
          : '/wallet-pass/vault/${widget.itemId}';

      final res = await apiClient.post(endpoint, {'platform': platform});
      if (res.statusCode != 200) {
        final msg = jsonDecode(res.body)['message'] ?? 'Failed to generate pass';
        throw Exception(msg);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _passData = body['pass'] as Map<String, dynamic>?;
        _saveUrl = body['saveUrl'] as String?;
        _platform = platform;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.card,
        title: Text('Add to Wallet',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: colors.textPrimary),
        elevation: 0,
      ),
      body: _busy
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _passData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: colors.danger),
                      const SizedBox(height: 16),
                      Text('Failed to generate pass', style: TextStyle(color: colors.textSecondary)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // ── Platform switcher ──
                    Row(
                      children: [
                        _PlatformChip(
                          label: 'Apple',
                          icon: Icons.phone_iphone,
                          selected: _platform == 'apple',
                          colors: colors,
                          onTap: () => _generatePass('apple'),
                        ),
                        const SizedBox(width: 8),
                        _PlatformChip(
                          label: 'Google',
                          icon: Icons.android,
                          selected: _platform == 'google',
                          colors: colors,
                          onTap: () => _generatePass('google'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Pass preview ──
                    _PassPreview(pass: _passData!, platform: _platform!, colors: colors)
                        .animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),

                    const SizedBox(height: 24),

                    // ── Add to wallet button ──
                    if (_platform == 'apple')
                      _AppleWalletButton(colors: colors, onTap: _addToAppleWallet)
                    else
                      _GoogleWalletButton(colors: colors, onTap: _addToGoogleWallet),

                    const SizedBox(height: 16),

                    // ── Info text ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.divider),
                      ),
                      child: Text(
                        _platform == 'apple'
                            ? 'The pass will be downloaded as a .pkpass file. Open it with Wallet app to add it to your Apple Wallet.'
                            : 'Tap "Save to Google Wallet" to add this pass directly to your Google Wallet app.',
                        style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _addToAppleWallet() async {
    if (_passData == null) return;
    setState(() => _busy = true);
    try {
      // Create a pass.json file (in production, this would be a signed .pkpass)
      final passJson = jsonEncode(_passData);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/azaman_${widget.passType}_${widget.itemId}.pkpass');
      await file.writeAsString(passJson);

      // Share the file — on iOS, this opens the share sheet where Wallet is an option
      await Share.shareXFiles([XFile(file.path)], text: 'Add to Apple Wallet');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addToGoogleWallet() async {
    if (_saveUrl != null) {
      // In production: launch URL to Google Wallet save link
      // For now, show the save URL
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening Google Wallet...')),
        );
      }
    }
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _PlatformChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _PlatformChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? colors.accent : colors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? Colors.white : colors.textSecondary, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(color: selected ? Colors.white : colors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _PassPreview extends StatelessWidget {
  final Map<String, dynamic> pass;
  final String platform;
  final AzamanColors colors;

  const _PassPreview({required this.pass, required this.platform, required this.colors});

  @override
  Widget build(BuildContext context) {
    final bgColor = _parseColor(pass['backgroundColor'] as String?, const Color(0xFF1A1A2E));
    final fgColor = _parseColor(pass['foregroundColor'] as String?, Colors.white);
    final labelColor = _parseColor(pass['labelColor'] as String?, Colors.white70);

    final storeCard = pass['storeCard'] as Map<String, dynamic>?;
    final generic = pass['generic'] as Map<String, dynamic>?;
    final passContent = storeCard ?? generic ?? {};
    final primaryFields = passContent['primaryFields'] as List<dynamic>? ?? [];
    final secondaryFields = passContent['secondaryFields'] as List<dynamic>? ?? [];
    final auxiliaryFields = passContent['auxiliaryFields'] as List<dynamic>? ?? [];

    final barcode = pass['barcode'] as Map<String, dynamic>?;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    pass['logoText'] as String? ?? 'AZAMAN',
                    style: TextStyle(color: fgColor, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  pass['description'] as String? ?? '',
                  style: TextStyle(color: labelColor, fontSize: 12),
                ),
              ],
            ),
          ),

          // ── Primary fields ──
          if (primaryFields.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: primaryFields.map((f) {
                  final field = f as Map<String, dynamic>;
                  return Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(field['label'] as String? ?? '',
                            style: TextStyle(color: labelColor, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(field['value'] as String? ?? '',
                            style: TextStyle(color: fgColor, fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 16),

          // ── Secondary fields ──
          if (secondaryFields.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: secondaryFields.map((f) {
                  final field = f as Map<String, dynamic>;
                  return Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(field['label'] as String? ?? '',
                            style: TextStyle(color: labelColor, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(field['value'] as String? ?? '',
                            style: TextStyle(color: fgColor, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 12),

          // ── Auxiliary fields ──
          if (auxiliaryFields.isNotEmpty) ...[
            const Divider(color: Colors.white24, indent: 20, endIndent: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: auxiliaryFields.map((f) {
                  final field = f as Map<String, dynamic>;
                  return Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(field['label'] as String? ?? '',
                            style: TextStyle(color: labelColor, fontSize: 10)),
                        Text(field['value'] as String? ?? '',
                            style: TextStyle(color: fgColor, fontSize: 13)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // ── Barcode area ──
          if (barcode != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // QR placeholder
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.qr_code_2, size: 80, color: Colors.black),
                  ),
                  const SizedBox(height: 8),
                  Text(barcode['altText'] as String? ?? '',
                      style: const TextStyle(color: Colors.black54, fontSize: 12, letterSpacing: 2)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _parseColor(String? rgbStr, Color fallback) {
    if (rgbStr == null) return fallback;
    try {
      // Parse "rgb(255,215,0)" format
      final match = RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)').firstMatch(rgbStr);
      if (match != null) {
        return Color.fromARGB(255, int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!));
      }
    } catch (_) {}
    return fallback;
  }
}

class _AppleWalletButton extends StatelessWidget {
  final AzamanColors colors;
  final VoidCallback onTap;
  const _AppleWalletButton({required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.wallet, size: 20),
        label: const Text('Add to Apple Wallet', style: TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _GoogleWalletButton extends StatelessWidget {
  final AzamanColors colors;
  final VoidCallback onTap;
  const _GoogleWalletButton({required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.account_balance_wallet, size: 20),
        label: const Text('Save to Google Wallet', style: TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4285F4),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

// =============================================================================
// AZAMAN — BUSINESS CHECK-IN SCREEN (2026-07-02)
//
// Two-mode check-in for businesses:
//   1. QR Scanner mode — camera scans customer's QR token
//   2. AZM-ID search mode — manual entry when scanner is unavailable
//
// On successful check-in, shows a confirmation card with customer details.
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';

class BusinessCheckInScreen extends ConsumerStatefulWidget {
  const BusinessCheckInScreen({super.key});

  @override
  ConsumerState<BusinessCheckInScreen> createState() => _BusinessCheckInScreenState();
}

enum _CheckInMode { scanner, search }

class _BusinessCheckInScreenState extends ConsumerState<BusinessCheckInScreen> with SingleTickerProviderStateMixin {
  _CheckInMode _mode = _CheckInMode.scanner;
  final _azamanIdController = TextEditingController();
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;
  late AnimationController _scanCtrl;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _azamanIdController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final checkInState = ref.watch(checkInActionProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Check-In Customer', style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: checkInState.result != null
          ? _buildSuccessView(checkInState.result!, colors)
          : checkInState.searchResult != null
              ? _buildSearchResults(checkInState.searchResult!, colors)
              : _buildMainView(colors, checkInState),
    );
  }

  // ── MAIN VIEW (scanner or search) ───────────────────────────────────────────

  Widget _buildMainView(dynamic colors, CheckInActionState checkInState) {
    return Column(
      children: [

        // Loading indicator
        if (checkInState.isLoading)
          const LinearProgressIndicator(),

        // Error message
        if (checkInState.error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(checkInState.error!,
                style: TextStyle(color: colors.danger, fontSize: 13)),
          ),

        // Mode content
        Expanded(
          child: _mode == _CheckInMode.scanner
              ? _buildScanner(colors)
              : _buildSearch(colors),
        ),
      ],
    );
  }

  // ── SCANNER ─────────────────────────────────────────────────────────────────

  Widget _buildScanner(dynamic colors) {
    return AnimatedBuilder(
      animation: _scanCtrl,
      builder: (context, child) {
        final screenHeight = MediaQuery.of(context).size.height;
        final scanLineY = (screenHeight / 2 - 120) + (_scanCtrl.value * 240);
        return Stack(
          children: [
            MobileScanner(
              controller: _scannerController,
              onDetect: _onDetect,
            ),
            // Dark overlay with transparent center frame
            ColorFiltered(
              colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.5), BlendMode.srcOver),
              child: Center(child: Container(width: 240, height: 240,
                decoration: BoxDecoration(border: Border.all(color: colors.accent, width: 2), borderRadius: BorderRadius.circular(20)))),
            ),
            // Animated scan line
            Positioned(
              left: MediaQuery.of(context).size.width / 2 - 120, right: MediaQuery.of(context).size.width / 2 - 120,
              top: scanLineY,
              child: Container(height: 2, decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.transparent, colors.accent, Colors.transparent]),
                boxShadow: [BoxShadow(color: colors.accent.withValues(alpha: 0.5), blurRadius: 8)])),
            ),
            // Corner brackets
            ..._buildCornerBrackets(colors, context),
            // Mode toggle pill at bottom
            Positioned(bottom: 32, left: 0, right: 0, child: Center(
              child: PremiumGlassContainer(
                blur: 16, opacity: 0.1, borderRadius: 24,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), enableShadow: false,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _modeButton('Scan', _CheckInMode.scanner, colors),
                  _modeButton('Search', _CheckInMode.search, colors),
                ]),
              ),
            )),
          ],
        );
      }
    );
  }

  List<Widget> _buildCornerBrackets(dynamic colors, BuildContext context) {
    const s = 20.0;
    const t = 4.0;
    final cx = MediaQuery.of(context).size.width / 2;
    final cy = MediaQuery.of(context).size.height / 2;
    const w2 = 120.0;
    
    return [
      Positioned(left: cx - w2, top: cy - w2, child: Container(width: s, height: t, color: colors.accent)),
      Positioned(left: cx - w2, top: cy - w2, child: Container(width: t, height: s, color: colors.accent)),
      Positioned(right: cx - w2, top: cy - w2, child: Container(width: s, height: t, color: colors.accent)),
      Positioned(right: cx - w2, top: cy - w2, child: Container(width: t, height: s, color: colors.accent)),
      Positioned(left: cx - w2, bottom: cy - w2, child: Container(width: s, height: t, color: colors.accent)),
      Positioned(left: cx - w2, bottom: cy - w2, child: Container(width: t, height: s, color: colors.accent)),
      Positioned(right: cx - w2, bottom: cy - w2, child: Container(width: s, height: t, color: colors.accent)),
      Positioned(right: cx - w2, bottom: cy - w2, child: Container(width: t, height: s, color: colors.accent)),
    ];
  }

  Widget _modeButton(String label, _CheckInMode m, dynamic colors) {
    final active = _mode == m;
    return GestureDetector(
      onTap: () => setState(() => _mode = m),
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          color: active ? Colors.white : colors.textPrimary,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    _isProcessing = true;
    final rawValue = barcode!.rawValue!;

    // Parse the QR payload — it's a JSON string: {"token":"...","type":"AZAMAN_CHECKIN"}
    // Or it could be a bare token string.
    String token;
    try {
      if (rawValue.startsWith('{')) {
        final payload = jsonDecode(rawValue) as Map<String, dynamic>;
        token = payload['token'] as String? ?? rawValue;
      } else {
        token = rawValue;
      }
    } catch (_) {
      token = rawValue;
    }

    ref.read(checkInActionProvider.notifier).verifyToken(token).then((_) {
      _isProcessing = false;
    }).catchError((_) {
      _isProcessing = false;
    });
  }

  // ── SEARCH ──────────────────────────────────────────────────────────────────

  Widget _buildSearch(dynamic colors) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manual Check-In',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary)),
          const SizedBox(height: 8),
          Text('Enter the customer\'s AZM-ID to find their reservation.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          TextField(
            controller: _azamanIdController,
            decoration: InputDecoration(
              labelText: 'AZM-ID',
              hintText: 'e.g. AZM-ABC123',
              prefixIcon: const Icon(Icons.badge),
              border: const OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.divider)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.accent, width: 2)),
            ),
            onSubmitted: (_) => _doSearch(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _doSearch,
              icon: const Icon(Icons.search),
              label: const Text('Search'),
            ),
          ),
        ],
      ),
    );
  }

  void _doSearch() {
    final azmId = _azamanIdController.text.trim();
    if (azmId.isEmpty) return;
    ref.read(checkInActionProvider.notifier).searchByAzamanId(azmId);
  }

  // ── SEARCH RESULTS ──────────────────────────────────────────────────────────

  Widget _buildSearchResults(AzamanIdSearchResult result, dynamic colors) {
    return Column(
      children: [
        // Customer header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: colors.surface,
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: result.profilePictureUrl != null
                    ? NetworkImage(result.profilePictureUrl!)
                    : null,
                child: result.profilePictureUrl == null
                    ? Text(result.username.isNotEmpty ? result.username[0].toUpperCase() : '?')
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.username,
                        style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)),
                    Text(result.azamanId,
                        style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Reservations list
        Expanded(
          child: result.reservations.isEmpty
              ? Center(
                  child: Text('No active reservations for this customer at your business',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textSecondary)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: result.reservations.length,
                  itemBuilder: (context, index) {
                    final res = result.reservations[index];
                    return Card(
                      color: colors.surface,
                      child: ListTile(
                        leading: const Icon(Icons.event_available),
                        title: Text(res.reservationRef,
                            style: TextStyle(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                        subtitle: Text(
                          '${_formatDate(res.startDatetime)} \u00b7 \$${res.amountUsdc.toStringAsFixed(2)}',
                          style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        ),
                        trailing: FilledButton(
                          onPressed: () => ref.read(checkInActionProvider.notifier).directCheckIn(res.id),
                          child: const Text('Check In'),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Back button
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextButton(
            onPressed: () => ref.read(checkInActionProvider.notifier).reset(),
            child: const Text('Search Again'),
          ),
        ),
      ],
    );
  }

  // ── SUCCESS VIEW ────────────────────────────────────────────────────────────

  Widget _buildSuccessView(CheckInResult result, dynamic colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Checkmark animation
            Container(
              width: 80, height: 80,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 24),

            Text('Checked In!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.textPrimary)),
            const SizedBox(height: 8),

            // Customer name
            if (result.customerUsername != null)
              Text(result.customerUsername!,
                  style: TextStyle(fontSize: 18, color: colors.textPrimary)),
            const SizedBox(height: 4),

            // AZM-ID
            if (result.customerAzamanId != null)
              Text(result.customerAzamanId!,
                  style: TextStyle(color: colors.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),

            // Reservation ref
            if (result.reservationRef.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Ref: ${result.reservationRef}',
                    style: TextStyle(color: colors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 32),

            // Done button
            FilledButton(
              onPressed: () {
                ref.read(checkInActionProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── MODE TAB WIDGET ──────────────────────────────────────────────────────────

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final dynamic colors;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? colors.accent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: isActive ? colors.accent : colors.textSecondary, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  color: isActive ? colors.accent : colors.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 12,
                )),
          ],
        ),
      ),
    );
  }
}

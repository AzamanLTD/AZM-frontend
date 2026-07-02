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

class BusinessCheckInScreen extends ConsumerStatefulWidget {
  const BusinessCheckInScreen({super.key});

  @override
  ConsumerState<BusinessCheckInScreen> createState() => _BusinessCheckInScreenState();
}

enum _CheckInMode { scanner, search }

class _BusinessCheckInScreenState extends ConsumerState<BusinessCheckInScreen> {
  _CheckInMode _mode = _CheckInMode.scanner;
  final _azamanIdController = TextEditingController();
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
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
        // Mode toggle
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ModeTab(
                  label: 'Scan QR',
                  icon: Icons.qr_code_scanner,
                  isActive: _mode == _CheckInMode.scanner,
                  onTap: () => setState(() => _mode = _CheckInMode.scanner),
                  colors: colors,
                ),
              ),
              Expanded(
                child: _ModeTab(
                  label: 'Search AZM-ID',
                  icon: Icons.search,
                  isActive: _mode == _CheckInMode.search,
                  onTap: () => setState(() => _mode = _CheckInMode.search),
                  colors: colors,
                ),
              ),
            ],
          ),
        ),

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
              color: colors.danger.withOpacity(0.1),
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
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
        ),
        // Overlay
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.3),
            BlendMode.srcOver,
          ),
          child: Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: colors.accent, width: 3),
                borderRadius: BorderRadius.circular(16),
                color: Colors.transparent,
              ),
            ),
          ),
        ),
        // Instructions
        Positioned(
          bottom: 32,
          left: 32,
          right: 32,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.qr_code_2, color: colors.accent, size: 32),
                const SizedBox(height: 8),
                Text('Point the camera at the customer\'s QR code',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14)),
              ],
            ),
          ),
        ),
      ],
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
              decoration: BoxDecoration(
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
                  color: colors.accent.withOpacity(0.1),
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
          color: isActive ? colors.accent.withOpacity(0.1) : Colors.transparent,
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

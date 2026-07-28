// =============================================================================
// AZAMAN — CHECK-IN QR SCREEN (Customer Side) (2026-07-02)
//
// Shows the customer a QR code that the business can scan to check them in.
// The QR token is HMAC-signed and expires in 30 minutes.
//
// Flow:
//   1. Customer opens this screen from their confirmed reservation detail
//   2. App calls GET /api/marketplace/reservations/:id/checkin-qr
//   3. QR code is rendered on screen
//   4. Business scans it → customer sees check-in confirmation
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/widgets/premium_glass_container.dart';

class CheckInQrScreen extends ConsumerStatefulWidget {
  final String reservationId;
  final String? businessName;

  const CheckInQrScreen({
    super.key,
    required this.reservationId,
    this.businessName,
  });

  @override
  ConsumerState<CheckInQrScreen> createState() => _CheckInQrScreenState();
}

class _CheckInQrScreenState extends ConsumerState<CheckInQrScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final tokenAsync = ref.watch(checkInTokenProvider(widget.reservationId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Check-In QR', style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: Center(
        child: tokenAsync.when(
          loading: () => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Generating your QR code...',
                  style: TextStyle(color: colors.textSecondary)),
            ],
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: colors.danger),
                const SizedBox(height: 16),
                Text('Could not generate QR',
                    style: TextStyle(fontSize: 18, color: colors.textPrimary)),
                const SizedBox(height: 8),
                Text(err.toString().replaceFirst('MarketplaceBookingException: ', ''),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textSecondary)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(checkInTokenProvider(widget.reservationId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
          data: (token) => _buildQrCard(token, colors),
        ),
      ),
    );
  }

  Widget _buildQrCard(CheckInToken token, dynamic colors) {
    return Card(
      margin: const EdgeInsets.all(24),
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Business name
            if (token.businessName != null) ...[
              Text(token.businessName!,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.textPrimary)),
              const SizedBox(height: 8),
            ],

            // AZM-ID badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                token.azamanId,
                style: TextStyle(fontWeight: FontWeight.bold, color: colors.accent, fontSize: 13),
              ),
            ),
            const SizedBox(height: 24),

            // QR code — rendered as a simple grid from the payload string
            // In production, use qr_flutter package for actual QR rendering
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) => Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: colors.accent.withValues(alpha: 0.15 * _pulseAnimation.value), blurRadius: 30 * _pulseAnimation.value, spreadRadius: 5 * _pulseAnimation.value)],
                ),
                child: PremiumGlassContainer(
                  blur: 20, opacity: 0.08, borderRadius: 20, padding: const EdgeInsets.all(16),
                  child: _buildQrPlaceholder(token.qrPayload, colors),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Reservation ref
            Text(
              'Ref: ${token.reservationRef}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),

            // Expiry countdown
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer, size: 16, color: colors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Valid for 30 minutes',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Info text
            Text(
              'Show this QR code to the business to check in',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  /// Placeholder QR rendering — in production, use the qr_flutter package.
  /// For now, we show a visual representation of the token hash.
  Widget _buildQrPlaceholder(String payload, dynamic colors) {
    // Generate a deterministic visual from the payload
    final bytes = utf8.encode(payload);
    final gridSize = 8;
    final cellSize = 24.0;

    return SizedBox(
      width: gridSize * cellSize,
      height: gridSize * cellSize,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridSize,
          childAspectRatio: 1,
        ),
        itemCount: gridSize * gridSize,
        itemBuilder: (context, index) {
          final byteIndex = index % bytes.length;
          final isFilled = (bytes[byteIndex] >> (index % 8)) & 1 == 1;
          // Corner markers (like real QR codes)
          final isCorner = (index < 3 || index % gridSize < 3 || index >= gridSize * (gridSize - 3));
          return Container(
            margin: const EdgeInsets.all(1),
            color: isFilled || isCorner ? Colors.black : Colors.white,
          );
        },
      ),
    );
  }
}

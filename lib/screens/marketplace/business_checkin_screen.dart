// =============================================================================
// AZAMAN — BUSINESS CHECK-IN SCREEN (2026-07-02)
//
// Two-mode check-in for businesses:
//   1. QR Scanner mode — camera scans customer's QR token
//   2. AZM-ID search mode — manual entry when scanner is unavailable
//
// On successful check-in, shows a confirmation card with customer details.
//
// Transit: the AZM-ID search also lists the passenger's trips with this
// business. Staff can board a paid passenger after checking their ID
// (photo, AZM-ID, name on ID) beside the QR, unless the business boards by
// QR only (Boarding rules, top right). The passenger is told and can
// confirm or report it; an unconfirmed fare is paid out later.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:flutter_animate/flutter_animate.dart';

class BusinessCheckInScreen extends ConsumerStatefulWidget {
  const BusinessCheckInScreen({super.key});

  @override
  ConsumerState<BusinessCheckInScreen> createState() =>
      _BusinessCheckInScreenState();
}

enum _CheckInMode { scanner, search }

class _BusinessCheckInScreenState extends ConsumerState<BusinessCheckInScreen>
    with SingleTickerProviderStateMixin {
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
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
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
        title: Text(
          'Check-In Customer',
          style: TextStyle(color: colors.textPrimary),
        ),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
        actions: [
          IconButton(
            key: const ValueKey('boarding-rules'),
            tooltip: 'Boarding rules',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _openBoardingRules(colors),
          ),
        ],
      ),
      body: checkInState.result != null
          ? _buildSuccessView(checkInState.result!, colors)
          : checkInState.searchResult != null
          ? _buildSearchResults(
              checkInState.searchResult!,
              colors,
              checkInState,
            )
          : _buildMainView(colors, checkInState),
    );
  }

  // ── MAIN VIEW (scanner or search) ───────────────────────────────────────────

  Widget _buildMainView(dynamic colors, CheckInActionState checkInState) {
    return Column(
      children: [
        // Loading indicator
        if (checkInState.isLoading) const LinearProgressIndicator(),

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
            child: Text(
              checkInState.error!,
              style: TextStyle(color: colors.danger, fontSize: 13),
            ),
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
            MobileScanner(controller: _scannerController, onDetect: _onDetect),
            // Dark overlay with transparent center frame
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.5),
                BlendMode.srcOver,
              ),
              child: Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.accent, width: 2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            // Animated scan line
            Positioned(
              left: MediaQuery.of(context).size.width / 2 - 120,
              right: MediaQuery.of(context).size.width / 2 - 120,
              top: scanLineY,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      colors.accent,
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.accent.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            // Corner brackets
            ..._buildCornerBrackets(colors, context),
            // Mode toggle pill at bottom
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: PremiumGlassContainer(
                  blur: 16,
                  opacity: 0.1,
                  borderRadius: 24,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  enableShadow: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _modeButton('Scan', _CheckInMode.scanner, colors),
                      _modeButton('Search', _CheckInMode.search, colors),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildCornerBrackets(dynamic colors, BuildContext context) {
    const s = 20.0;
    const t = 4.0;
    final cx = MediaQuery.of(context).size.width / 2;
    final cy = MediaQuery.of(context).size.height / 2;
    const w2 = 120.0;

    return [
      Positioned(
        left: cx - w2,
        top: cy - w2,
        child: Container(width: s, height: t, color: colors.accent),
      ),
      Positioned(
        left: cx - w2,
        top: cy - w2,
        child: Container(width: t, height: s, color: colors.accent),
      ),
      Positioned(
        right: cx - w2,
        top: cy - w2,
        child: Container(width: s, height: t, color: colors.accent),
      ),
      Positioned(
        right: cx - w2,
        top: cy - w2,
        child: Container(width: t, height: s, color: colors.accent),
      ),
      Positioned(
        left: cx - w2,
        bottom: cy - w2,
        child: Container(width: s, height: t, color: colors.accent),
      ),
      Positioned(
        left: cx - w2,
        bottom: cy - w2,
        child: Container(width: t, height: s, color: colors.accent),
      ),
      Positioned(
        right: cx - w2,
        bottom: cy - w2,
        child: Container(width: s, height: t, color: colors.accent),
      ),
      Positioned(
        right: cx - w2,
        bottom: cy - w2,
        child: Container(width: t, height: s, color: colors.accent),
      ),
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
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? (colors.isDark ? Colors.black : Colors.white)
                : colors.textPrimary,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    _isProcessing = true;
    final rawValue = barcode!.rawValue!;

    // A hotel check-in code or a transit boarding pass: verifyScan reads
    // which (checkin_scan.dart) and sends it to the endpoint that verifies
    // it. Boarding a paid passenger by their code is what releases the fare
    // to the operator when the trip completes.
    ref
        .read(checkInActionProvider.notifier)
        .verifyScan(rawValue)
        .then((_) {
          _isProcessing = false;
        })
        .catchError((_) {
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
          // The way back to the scanner (it used to live only on the
          // camera view, so Search was one-way).
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.divider, width: 0.6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _modeButton('Scan', _CheckInMode.scanner, colors),
                  _modeButton('Search', _CheckInMode.search, colors),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Manual Check-In',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the customer\'s AZM-ID to find their reservations and trips.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _azamanIdController,
            decoration: InputDecoration(
              labelText: 'AZM-ID',
              hintText: 'e.g. AZM-000004242',
              prefixIcon: const Icon(Icons.badge),
              border: const OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colors.accent, width: 2),
              ),
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

  Widget _buildSearchResults(
    AzamanIdSearchResult result,
    dynamic colors,
    CheckInActionState st,
  ) {
    final trips = result.transitBookings;
    return Column(
      children: [
        if (st.isLoading) const LinearProgressIndicator(),
        if (st.error != null)
          Container(
            key: const ValueKey('checkin-search-error'),
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              st.error!,
              style: TextStyle(color: colors.danger, fontSize: 13),
            ),
          ),
        _PassengerHeader(card: result.card, colors: colors),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (trips.isNotEmpty) ...[
                _sectionLabel('Trips', colors),
                for (final t in trips)
                  _TripBoardingCard(
                    booking: t,
                    allowIdCheck: result.allowIdCheck,
                    busy: st.isLoading,
                    colors: colors,
                    onBoard: () => _confirmIdBoarding(t, result, colors),
                  ),
                const SizedBox(height: 12),
              ],
              if (result.reservations.isNotEmpty) ...[
                _sectionLabel('Reservations', colors),
                for (final res in result.reservations)
                  Card(
                    color: colors.surface,
                    child: ListTile(
                      leading: const Icon(Icons.event_available),
                      title: Text(
                        res.reservationRef,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        '${_formatDate(res.startDatetime)} \u00b7 \$${res.amountUsdc.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      trailing: FilledButton(
                        onPressed: () => ref
                            .read(checkInActionProvider.notifier)
                            .directCheckIn(res.id),
                        child: const Text('Check In'),
                      ),
                    ),
                  ),
              ],
              if (trips.isEmpty && result.reservations.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Text(
                    'No upcoming trips or reservations for this customer at your business.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
            ],
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

  Widget _sectionLabel(String text, dynamic colors) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 11.5,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  /// Staff compare the person and their photo ID with the account before
  /// anything is sent. The AZM-ID goes with the request as that check.
  Future<void> _confirmIdBoarding(
    TransitPassengerBooking booking,
    AzamanIdSearchResult result,
    dynamic colors,
  ) async {
    final card = booking.passenger ?? result.card;
    final first = card.shownName.split(' ').first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check their ID'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(card: card, radius: 40),
              const SizedBox(height: 12),
              Text(
                card.shownName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _IdLine(
                label: 'Name on ID',
                value: card.legalName ?? 'Not on file. Compare the photo.',
              ),
              _IdLine(label: 'AZM-ID', value: card.azamanId, tabular: true),
              if (booking.seatIds.isNotEmpty)
                _IdLine(
                  label: booking.seatIds.length == 1 ? 'Seat' : 'Seats',
                  value: booking.seatIds.join(', '),
                ),
              if (card.idVerified)
                const _IdLine(label: 'Account', value: 'ID verified'),
              const SizedBox(height: 12),
              Text(
                'Board only if the person and their photo ID match this account. '
                'We will ask $first to confirm it.',
                style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const ValueKey('confirm-board-by-id'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Board $first'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(checkInActionProvider.notifier).boardByIdCheck(booking);
    }
  }

  /// The owner's rule: may staff board by ID check, or QR only?
  Future<void> _openBoardingRules(dynamic colors) async {
    final svc = ref.read(marketplaceBookingServiceProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      showDragHandle: true,
      builder: (ctx) => _BoardingRulesSheet(
        load: svc.transitBoardingAllowsIdCheck,
        save: svc.setTransitBoardingAllowsIdCheck,
        colors: colors,
      ),
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
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.success,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                color: colors.isDark ? Colors.black : Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 24),

            Text(
              result.isTransit ? 'Boarded' : 'Checked In!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            if (result.boardedByIdCheck) ...[
              const SizedBox(height: 4),
              Text(
                'By ID check',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),

            // Customer name
            if (result.customerUsername != null)
              Text(
                result.customerUsername!,
                style: TextStyle(fontSize: 18, color: colors.textPrimary),
              ),
            const SizedBox(height: 4),

            // AZM-ID
            if (result.customerAzamanId != null)
              Text(
                result.customerAzamanId!,
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
            const SizedBox(height: 16),

            // Reservation ref
            if (result.reservationRef.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Ref: ${result.reservationRef}',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (result.boardedByIdCheck && (result.fareHeldHours ?? 0) > 0) ...[
              const SizedBox(height: 16),
              Text(
                'We have asked ${result.customerUsername ?? 'the passenger'} to confirm. '
                'If they do not, the fare is paid to you '
                '${result.fareHeldHours} hours after departure.',
                key: const ValueKey('id-check-payout-note'),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 32),

            // Next customer keeps the scanner or search open; Close leaves.
            FilledButton(
              key: const ValueKey('checkin-next'),
              onPressed: () => ref.read(checkInActionProvider.notifier).reset(),
              child: const Text('Next customer'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                ref.read(checkInActionProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
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

// ── ID-CHECK WIDGETS ─────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.card, this.radius = 28});
  final PassengerIdCard card;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = card.profilePictureUrl;
    final name = card.shownName;
    return CircleAvatar(
      radius: radius,
      backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: url == null || url.isEmpty
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(fontSize: radius * 0.7),
            )
          : null,
    );
  }
}

class _IdLine extends StatelessWidget {
  const _IdLine({
    required this.label,
    required this.value,
    this.tabular = false,
  });
  final String label;
  final String value;
  final bool tabular;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).hintColor,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              fontFeatures: tabular ? AzText.tabular : null,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The looked-up customer as staff check them: photo, name, name on ID,
/// AZM-ID, and whether the account's ID is verified.
class _PassengerHeader extends StatelessWidget {
  const _PassengerHeader({required this.card, required this.colors});
  final PassengerIdCard card;
  final dynamic colors;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    color: colors.surface,
    child: Row(
      children: [
        _Avatar(card: card, radius: 32),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.shownName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: colors.textPrimary,
                ),
              ),
              if (card.legalName != null)
                Text(
                  'Name on ID: ${card.legalName}',
                  key: const ValueKey('passenger-legal-name'),
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    card.azamanId,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                      fontFeatures: AzText.tabular,
                    ),
                  ),
                  if (card.idVerified) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.verified_user_rounded,
                      size: 14,
                      color: colors.success,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'ID verified',
                      style: TextStyle(color: colors.success, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One of the passenger's trips: where, when, seats, whether it is paid,
/// and what staff can do now.
class _TripBoardingCard extends StatelessWidget {
  const _TripBoardingCard({
    required this.booking,
    required this.allowIdCheck,
    required this.busy,
    required this.colors,
    required this.onBoard,
  });
  final TransitPassengerBooking booking;
  final bool allowIdCheck;
  final bool busy;
  final dynamic colors;
  final VoidCallback onBoard;

  String _time(BuildContext context, DateTime at) => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));

  Widget _note(String text) =>
      Text(text, style: TextStyle(color: colors.textSecondary, fontSize: 12.5));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final b = booking;
    final when = b.departureAt == null
        ? null
        : '${MaterialLocalizations.of(context).formatShortDate(b.departureAt!.toLocal())} · ${_time(context, b.departureAt!)}';
    final Widget action;
    if (b.isOnBoard) {
      action = _note(
        b.boardingMethod == 'ID_CHECK' ? 'On board · by ID check' : 'On board',
      );
    } else if (!b.isWaiting) {
      action = _note(b.status);
    } else if (b.canBoardById) {
      action = FilledButton.icon(
        key: ValueKey('board-by-id-${b.id}'),
        onPressed: busy ? null : onBoard,
        icon: const Icon(Icons.badge_outlined, size: 18),
        label: const Text('Board after ID check'),
      );
    } else if (!allowIdCheck) {
      action = _note(
        'Your business boards by QR only. Ask for their boarding QR.',
      );
    } else if (b.boardingOpensAt != null && now.isBefore(b.boardingOpensAt!)) {
      action = _note('Boarding opens at ${_time(context, b.boardingOpensAt!)}');
    } else {
      action = _note('Boarding has closed for this trip.');
    }
    return Container(
      key: ValueKey('trip-boarding-${b.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${b.origin} → ${b.destination}',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            [
              if (when != null) when,
              if (b.seatIds.isNotEmpty)
                '${b.seatIds.length == 1 ? 'Seat' : 'Seats'} ${b.seatIds.join(', ')}',
              b.bookingRef,
            ].join(' · '),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12.5,
              fontFeatures: AzText.tabular,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            b.isPaid ? 'Paid in Azaman' : 'Not paid in the app',
            style: TextStyle(
              color: b.isPaid ? colors.success : colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          action,
        ],
      ),
    );
  }
}

class _BoardingRulesSheet extends StatefulWidget {
  const _BoardingRulesSheet({
    required this.load,
    required this.save,
    required this.colors,
  });
  final Future<bool> Function() load;
  final Future<bool> Function(bool) save;
  final dynamic colors;

  @override
  State<_BoardingRulesSheet> createState() => _BoardingRulesSheetState();
}

class _BoardingRulesSheetState extends State<_BoardingRulesSheet> {
  bool? _allow;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.load().then(
      (v) => mounted ? setState(() => _allow = v) : null,
      onError: (_) => mounted
          ? setState(() => _error = 'Could not load your boarding rules.')
          : null,
    );
  }

  Future<void> _set(bool v) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.save(v);
      if (mounted) setState(() => _allow = saved);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Boarding rules',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (_allow == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_allow != null)
              SwitchListTile(
                key: const ValueKey('allow-id-check'),
                contentPadding: EdgeInsets.zero,
                value: _allow!,
                onChanged: _saving ? null : _set,
                title: const Text('Allow boarding by ID check'),
                subtitle: Text(
                  _allow!
                      ? 'Staff can board a passenger after checking their photo ID against their AZM-ID. The passenger is asked to confirm.'
                      : 'QR only: passengers board with their own boarding QR.',
                ),
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
          ],
        ),
      ),
    );
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
          color: isActive
              ? colors.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive ? colors.accent : colors.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? colors.accent : colors.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

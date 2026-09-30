// =============================================================================
// HOTEL ARRIVAL SHEET — booking success as arrival (TASK-015)
//
// The transit path keeps BookingSuccessSheet; the hotel path celebrates as an
// ARRIVAL: the room door swings open on its hinge (perspective rotateY), warm
// light spills from the doorway, the key card materialises with a pop spring
// and a commit (heavy) haptic, and settles into a "Your stays" slot. Honest
// detail rows follow — no invented check-in times, no fake buttons.
//
// "Add to Wallet" ships in TASK-021 (artifact wallet); today
// wallet_pass_screen.dart only supports loyalty/vault passes, so this sheet
// renders the stays slot motif and stops there.
//
// TEST-SAFETY: two one-shot AnimationControllers chained with whenComplete —
// no Timers, no repeating tickers. Reduced motion collapses both to their
// final state via MotionTokens.accessibleDuration (checked once in
// didChangeDependencies, where MediaQuery lookups are legal).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/liquid/liquid_engine.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/services/az_sound.dart';

class HotelArrivalSheet extends ConsumerStatefulWidget {
  final String reservationRef;
  final HotelRoom room;
  final DateTime checkIn;
  final int nights;
  final double totalUsdc;

  const HotelArrivalSheet({
    super.key,
    required this.reservationRef,
    required this.room,
    required this.checkIn,
    required this.nights,
    required this.totalUsdc,
  });

  /// Convenience method to show the sheet.
  static Future<void> show(
    BuildContext context, {
    required String reservationRef,
    required HotelRoom room,
    required DateTime checkIn,
    required int nights,
    required double totalUsdc,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HotelArrivalSheet(
        reservationRef: reservationRef,
        room: room,
        checkIn: checkIn,
        nights: nights,
        totalUsdc: totalUsdc,
      ),
    );
  }

  @override
  ConsumerState<HotelArrivalSheet> createState() =>
      _HotelArrivalSheetState();
}

class _HotelArrivalSheetState extends ConsumerState<HotelArrivalSheet>
    with TickerProviderStateMixin {
  late final AnimationController _door;
  late final AnimationController _card;
  bool _started = false;
  bool _committed = false;
  Offset? _flight;

  // The key-card flight path: the card is born at the doorway and travels
  // down into the YOUR STAYS slot. Both anchors are measured from the live
  // render tree while the card animation runs, so the flight survives any
  // layout change and collapses to nothing under reduced motion (the card
  // controller jumps straight to 1.0, so no travel is ever painted).
  final GlobalKey _doorKey = GlobalKey(debugLabel: 'arrival-door');
  final GlobalKey _slotKey = GlobalKey(debugLabel: 'stays-slot');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final doorDuration =
        MotionTokens.accessibleDuration(context, MotionTokens.spatial);
    _door = AnimationController(vsync: this, duration: doorDuration);
    _card = AnimationController(
      vsync: this,
      duration: MotionTokens.accessibleDuration(
          context, MotionTokens.emphasized),
    );
    _card.addStatusListener((status) {
      // The flight path is measured ONCE, when the card sets off: the door
      // stage and the stays slot are settled boxes from the previous frame
      // by then, so their global centres are valid without any timers.
      if (status == AnimationStatus.forward && _flight == null) {
        _flight = _flightVector();
      }
      if (status == AnimationStatus.completed && !_committed) {
        _committed = true;
        AzamanHaptics.commit();
        AzSound.success();
      }
    });
    if (doorDuration == Duration.zero) {
      _door.value = 1.0;
      _card.value = 1.0;
    } else {
      _door.forward().whenComplete(() => _card.forward());
    }
  }

  @override
  void dispose() {
    _door.dispose();
    _card.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final room = widget.room;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AzRadius.sheetTop,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _doorStage(colors),
              const SizedBox(height: AzSpace.xl),
              Text('YOUR ROOM IS READY',
                  style: AzText.eyebrow.copyWith(color: colors.textTertiary)),
              const SizedBox(height: AzSpace.xs),
              Text('Welcome to your stay',
                  style: AzText.titleXl.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AzSpace.lg),
              _staysSlot(colors),
              const SizedBox(height: AzSpace.xl),
              _row(colors, Icons.meeting_room_outlined, 'Room',
                  '${room.displayType} · Room ${room.roomNumber}'),
              _row(colors, Icons.calendar_today_rounded, 'Check-in',
                  '${widget.checkIn.day}/${widget.checkIn.month}'),
              _row(colors, Icons.nightlight_outlined, 'Nights',
                  '${widget.nights}'),
              _row(colors, Icons.payments_rounded, 'Total paid',
                  '\$${widget.totalUsdc.toStringAsFixed(2)} USDC'),
              _row(colors, Icons.receipt_long_outlined, 'Reference',
                  widget.reservationRef),
              const SizedBox(height: AzSpace.xl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                        borderRadius: AzRadius.brMd),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done', style: AzText.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _doorStage(AzamanColors colors) {
    return SizedBox(
      key: _doorKey,
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Light spilling from the doorway, gated by the door's progress.
          AnimatedBuilder(
            animation: _door,
            builder: (context, _) => Opacity(
              opacity: (_door.value * 0.9).clamp(0.0, 1.0).toDouble(),
              child: Container(
                width: 220,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: AzRadius.brLg,
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, 0),
                    radius: 1.1,
                    colors: [
                      const Color(0xFFFFE9B8).withValues(alpha: 0.95),
                      const Color(0xFFFFD98A).withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _door,
            builder: (context, _) {
              final open = Curves.easeOutCubic.transform(_door.value);
              return Transform(
                alignment: Alignment.centerLeft,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(-open * 1.15),
                child: _doorPanel(colors),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _doorPanel(AzamanColors colors) {
    return Container(
      width: 128,
      height: 152,
      padding: const EdgeInsets.all(AzSpace.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.card, colors.softSurface],
        ),
        borderRadius: AzRadius.brLg,
        border: Border.all(color: colors.divider.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AzSpace.sm, vertical: AzSpace.xs),
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: AzRadius.brSm,
            ),
            child: Text(
              widget.room.roomNumber,
              style: AzText.label.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            height: 44,
            decoration: BoxDecoration(
              border:
                  Border.all(color: colors.divider.withValues(alpha: 0.6)),
              borderRadius: AzRadius.brSm,
            ),
          ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// Vector from the card's rest position (inside the stays slot) back to
  /// the door stage where it is born. Translating by this amount at flight
  /// start places the card at the doorway; interpolating it to zero on
  /// kPopSpring carries it down into the slot. Both anchors are plain
  /// untransformed boxes (the door STAGE, not the perspective-rotated door
  /// panel), measured once at card start from the previous frame's settled
  /// layout — no timers, no repeating tickers.
  Offset _flightVector() {
    final doorBox = _doorKey.currentContext?.findRenderObject();
    final slotBox = _slotKey.currentContext?.findRenderObject();
    if (doorBox is! RenderBox || slotBox is! RenderBox) return Offset.zero;
    if (!doorBox.attached || !slotBox.attached) return Offset.zero;
    final doorCentre = doorBox
        .localToGlobal(doorBox.size.center(Offset.zero));
    final slotCentre = slotBox
        .localToGlobal(slotBox.size.center(Offset.zero));
    return doorCentre - slotCentre;
  }

  Widget _staysSlot(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('YOUR STAYS',
            style: AzText.eyebrow.copyWith(color: colors.textTertiary)),
        const SizedBox(height: AzSpace.sm),
        Container(
          key: _slotKey,
          width: double.infinity,
          padding: const EdgeInsets.all(AzSpace.md),
          decoration: BoxDecoration(
            color: colors.softSurface.withValues(alpha: 0.6),
            borderRadius: AzRadius.brLg,
            border: Border.all(color: colors.divider.withValues(alpha: 0.6)),
          ),
          child: Semantics(
            label: 'Key card for room ${widget.room.roomNumber}',
            child: AnimatedBuilder(
              animation: _card,
              builder: (context, child) {
                // The named key-card motion primitive from the liquid engine —
                // the planning source specifies kPopSpring here, not a
                // substituted curve. The spring drives BOTH the pop scale and
                // the flight: at t=0 the card sits at the doorway; as the
                // spring settles the travel vector eases to zero, leaving the
                // card resting inside the YOUR STAYS slot.
                final pop = kPopSpring.transform(_card.value);
                final flight = (_card.value >= 1 || _flight == null)
                    ? Offset.zero
                    : _flight! * (1 - pop);
                return Transform.translate(
                  offset: flight,
                  child: Opacity(
                    opacity: _card.value.clamp(0.0, 1.0).toDouble(),
                    child:
                        Transform.scale(scale: 0.6 + 0.4 * pop, child: child),
                  ),
                );
              },
              child: _keyCard(colors),
            ),
          ),
        ),
      ],
    );
  }

  Widget _keyCard(AzamanColors colors) {
    return Container(
      height: 72,
      padding:
          const EdgeInsets.symmetric(horizontal: AzSpace.lg, vertical: AzSpace.sm),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.accent, colors.accentSecondary],
        ),
        borderRadius: AzRadius.brMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'AZAMAN',
                  style: AzText.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: AzSpace.xxs),
                Text(
                  'ROOM ${widget.room.roomNumber}',
                  style: AzText.label.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
          Container(
            width: 26,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              borderRadius: AzRadius.brXs,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(AzamanColors colors, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AzSpace.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.textTertiary),
          const SizedBox(width: AzSpace.md),
          Text(
            label,
            style: AzText.bodyS.copyWith(
              color: colors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AzText.bodyS.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

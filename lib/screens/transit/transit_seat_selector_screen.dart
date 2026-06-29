import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

enum SeatStatus { available, selected, taken, aisle }

class TransitSeat {
  final String id;
  final int row;
  final int col;
  final SeatStatus status;
  final double priceUsdc;

  const TransitSeat({
    required this.id,
    required this.row,
    required this.col,
    this.status = SeatStatus.available,
    this.priceUsdc = 15.0,
  });
}

class TransitSeatSelectorScreen extends ConsumerStatefulWidget {
  final String routeName;
  final String departure;
  final String destination;
  final String date;
  final String time;

  const TransitSeatSelectorScreen({
    super.key,
    required this.routeName,
    required this.departure,
    required this.destination,
    required this.date,
    required this.time,
  });

  @override
  ConsumerState<TransitSeatSelectorScreen> createState() =>
      _TransitSeatSelectorScreenState();
}

class _TransitSeatSelectorScreenState
    extends ConsumerState<TransitSeatSelectorScreen> {
  late List<List<TransitSeat>> _seats;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _seats = _buildSeats();
  }

  List<List<TransitSeat>> _buildSeats() {
    final rows = <List<TransitSeat>>[];
    for (int r = 0; r < 10; r++) {
      final row = <TransitSeat>[];
      for (int c = 0; c < 4; c++) {
        if (c == 2) {
          row.add(TransitSeat(id: 'aisle-$r', row: r, col: c, status: SeatStatus.aisle));
        }
        final taken = r == 1 && c == 0 || r == 3 && c == 1 || r == 5 && c == 3 || r == 7 && c == 0;
        row.add(TransitSeat(
          id: '${r + 1}${String.fromCharCode(65 + c)}',
          row: r,
          col: c,
          status: taken ? SeatStatus.taken : SeatStatus.available,
          priceUsdc: c < 2 ? 15.0 : 20.0,
        ));
      }
      rows.add(row);
    }
    return rows;
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
    AzamanHaptics.light();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final total = _selected.length * 15.0;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text('Select Seats',
            style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          _tripInfo(colors),
          Expanded(child: _seatGrid(colors)),
          _legend(colors),
          _cta(colors, total),
        ],
      ),
    );
  }

  Widget _tripInfo(AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.routeName,
                    style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${widget.departure} → ${widget.destination}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                Text('${widget.date}  ${widget.time}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Icon(HugeIconsSolid.bus01, color: colors.accent, size: 28),
        ],
      ),
    );
  }

  Widget _seatGrid(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Text('SEATS', style: TextStyle(color: colors.textTertiary, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  children: _seats.map((row) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: row.map((seat) {
                          if (seat.status == SeatStatus.aisle) {
                            return const SizedBox(width: 24);
                          }
                          final selected = _selected.contains(seat.id);
                          final taken = seat.status == SeatStatus.taken;
                          return GestureDetector(
                            onTap: taken ? null : () => _toggle(seat.id),
                            child: Container(
                              width: 44,
                              height: 44,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: taken
                                    ? colors.textTertiary.withValues(alpha: 0.15)
                                    : selected
                                        ? colors.accent
                                        : colors.card,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: taken
                                      ? colors.divider
                                      : selected
                                          ? colors.accent
                                          : colors.divider,
                                  width: taken ? 0 : selected ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: taken
                                  ? Icon(HugeIconsSolid.lockKey, color: colors.textTertiary, size: 16)
                                  : selected
                                      ? Icon(HugeIconsSolid.checkmarkCircle01, color: colors.surface, size: 20)
                                      : Text(seat.id,
                                          style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendDot(colors, colors.card, 'Available'),
          const SizedBox(width: 20),
          _legendDot(colors, colors.accent, 'Selected'),
          const SizedBox(width: 20),
          _legendDot(colors, colors.textTertiary.withValues(alpha: 0.15), 'Taken'),
        ],
      ),
    );
  }

  Widget _legendDot(AzamanColors colors, Color dotColor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: dotColor, borderRadius: BorderRadius.circular(3), border: Border.all(color: colors.divider))),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 11)),
      ],
    );
  }

  Widget _cta(AzamanColors colors, double total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  AzamanHaptics.commit();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${_selected.length} seat(s) booked — \$${total.toStringAsFixed(2)} USDC'),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
          style: FilledButton.styleFrom(
            backgroundColor: colors.accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          child: Text(
            _selected.isEmpty
                ? 'Select seats to continue'
                : 'Book ${_selected.length} seat${_selected.length > 1 ? 's' : ''}  ·  \$${total.toStringAsFixed(2)} USDC',
            style: TextStyle(color: colors.surface, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

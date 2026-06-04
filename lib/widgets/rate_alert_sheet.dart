import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/rate_alert_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/rate_alert_service.dart';

// =============================================================================
// AZAMAN — RATE ALERT SHEET (Phase Q12-FE)
//
// Bottom sheet for creating rate alerts and viewing active/triggered alerts.
// Launched from the LiveMarketSection's "Set Alert" button.
// =============================================================================

class RateAlertSheet extends ConsumerStatefulWidget {
  final double? currentRate;

  const RateAlertSheet({super.key, this.currentRate});

  static void show(BuildContext context, WidgetRef ref, {double? currentRate}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ref.read(themeProvider).colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RateAlertSheet(currentRate: currentRate),
    );
  }

  @override
  ConsumerState<RateAlertSheet> createState() => _RateAlertSheetState();
}

class _RateAlertSheetState extends ConsumerState<RateAlertSheet> {
  final _rateController = TextEditingController();
  final _noteController = TextEditingController();
  String _direction = 'ABOVE';
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rateAlertProvider).fetchAlerts();
    });
  }

  @override
  void dispose() {
    _rateController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final rateText = _rateController.text.trim();
    final rate = double.tryParse(rateText);
    if (rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid target rate')),
      );
      return;
    }

    setState(() => _isCreating = true);

    final success = await ref.read(rateAlertProvider).createAlert(
      targetRate: rate,
      direction: _direction,
      note: _noteController.text.trim().isNotEmpty
          ? _noteController.text.trim()
          : null,
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (success) {
      HapticFeedback.mediumImpact();
      _rateController.clear();
      _noteController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alert set: notify when rate goes $_direction $rateText'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      final err = ref.read(rateAlertProvider).error ?? 'Failed to create alert';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final alertState = ref.watch(rateAlertProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Row(
                  children: [
                    Icon(Icons.notifications_active_rounded,
                        color: colors.accent, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Rate Alerts',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (widget.currentRate != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Now: ${widget.currentRate!.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: colors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Get notified when the USD→GHS rate hits your target.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 20),

                // ── Create Alert Form ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEW ALERT',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Target rate input
                      TextField(
                        controller: _rateController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Target rate (e.g. 15.50)',
                          hintStyle: TextStyle(color: colors.textTertiary),
                          prefixIcon: Icon(Icons.currency_exchange,
                              color: colors.accent, size: 20),
                          filled: true,
                          fillColor: colors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Direction toggle
                      Row(
                        children: [
                          _DirectionChip(
                            label: 'ABOVE',
                            icon: Icons.trending_up_rounded,
                            isSelected: _direction == 'ABOVE',
                            colors: colors,
                            onTap: () =>
                                setState(() => _direction = 'ABOVE'),
                          ),
                          const SizedBox(width: 10),
                          _DirectionChip(
                            label: 'BELOW',
                            icon: Icons.trending_down_rounded,
                            isSelected: _direction == 'BELOW',
                            colors: colors,
                            onTap: () =>
                                setState(() => _direction = 'BELOW'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Optional note
                      TextField(
                        controller: _noteController,
                        style: TextStyle(
                            color: colors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Label (optional)',
                          hintStyle: TextStyle(color: colors.textTertiary),
                          prefixIcon: Icon(Icons.label_outline,
                              color: colors.textTertiary, size: 18),
                          filled: true,
                          fillColor: colors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Create button
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _isCreating ? null : _handleCreate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor:
                                colors.isDark ? Colors.black : Colors.white,
                            disabledBackgroundColor:
                                colors.accent.withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isCreating
                              ? SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: colors.isDark
                                        ? Colors.black
                                        : Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Create Alert',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Active Alerts ─────────────────────────────────────────
                if (alertState.isLoading && !alertState.hasFetched)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: CircularProgressIndicator(color: colors.accent),
                    ),
                  )
                else if (alertState.alerts.isNotEmpty) ...[
                  Text(
                    'YOUR ALERTS',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...alertState.alerts.map(
                    (alert) => _AlertTile(
                      alert: alert,
                      colors: colors,
                      onDelete: () => _handleDelete(alert.id),
                    ),
                  ),
                ] else if (alertState.hasFetched) ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(Icons.notifications_none_rounded,
                              size: 36, color: colors.textTertiary),
                          const SizedBox(height: 8),
                          Text(
                            'No alerts yet',
                            style: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleDelete(String alertId) async {
    final success = await ref.read(rateAlertProvider).deleteAlert(alertId);
    if (mounted && success) {
      HapticFeedback.lightImpact();
    }
  }
}

// ── Direction Chip ──────────────────────────────────────────────────────────

class _DirectionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _DirectionChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.accent.withOpacity(0.12)
                : colors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? colors.accent : colors.divider,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: isSelected ? colors.accent : colors.textTertiary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? colors.accent : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Alert Tile ──────────────────────────────────────────────────────────────

class _AlertTile extends StatelessWidget {
  final RateAlert alert;
  final AzamanColors colors;
  final VoidCallback onDelete;

  const _AlertTile({
    required this.alert,
    required this.colors,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isTriggered = alert.isTriggered;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isTriggered ? colors.card.withOpacity(0.5) : colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTriggered
              ? colors.divider.withOpacity(0.5)
              : alert.direction == 'ABOVE'
                  ? colors.success.withOpacity(0.3)
                  : colors.danger.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // Direction icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (alert.direction == 'ABOVE'
                      ? colors.success
                      : colors.danger)
                  .withOpacity(isTriggered ? 0.05 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              alert.direction == 'ABOVE'
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              size: 16,
              color: isTriggered
                  ? colors.textTertiary
                  : alert.direction == 'ABOVE'
                      ? colors.success
                      : colors.danger,
            ),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${alert.direction} ${alert.targetRate.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isTriggered
                            ? colors.textTertiary
                            : colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        decoration:
                            isTriggered ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (isTriggered) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Triggered at ${alert.triggeredRate?.toStringAsFixed(2) ?? "—"}',
                          style: TextStyle(
                            color: colors.success,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (alert.note != null && alert.note!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    alert.note!,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Delete button (only for active)
          if (!isTriggered)
            IconButton(
              icon: Icon(Icons.close_rounded,
                  size: 18, color: colors.textTertiary),
              onPressed: onDelete,
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }
}

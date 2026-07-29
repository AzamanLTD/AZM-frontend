// =============================================================================
// AZAMAN — Vault DeFi Yield Screen (Phase 3)
//
// Shows available DeFi yield strategies, lets user enable/disable yield
// on their vault, shows projected earnings, daily yield, and supports
// manual compounding + auto-compound toggle.
//
// Reference: Aave front-end, Compound dashboard
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/vault_provider.dart';
import 'package:azaman/services/api_client.dart';

// ── Providers ───────────────────────────────────────────────────────────────

final yieldStrategiesProvider = FutureProvider<List<YieldStrategy>>((ref) async {
  final res = await apiClient.get('/vaults/yield/strategies');
  if (res.statusCode != 200) return [];
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final list = body['strategies'] as List<dynamic>? ?? [];
  return list.map((e) => YieldStrategy.fromJson(e as Map<String, dynamic>)).toList();
});

final vaultYieldEarningsProvider = FutureProvider.family<VaultYieldInfo, String>((ref, vaultId) async {
  final res = await apiClient.get('/vaults/$vaultId/yield/earnings');
  if (res.statusCode != 200) {
    return VaultYieldInfo(enabled: false);
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return VaultYieldInfo.fromJson(body['yield'] as Map<String, dynamic>);
});

// ── Models ──────────────────────────────────────────────────────────────────

class YieldStrategy {
  final String name;
  final String displayName;
  final String protocol;
  final double apr;
  final String riskLevel;
  final double minAmountUsdc;
  final double? maxAmountUsdc;
  final String? description;
  final String? logoUrl;

  YieldStrategy({
    required this.name,
    required this.displayName,
    required this.protocol,
    required this.apr,
    required this.riskLevel,
    required this.minAmountUsdc,
    this.maxAmountUsdc,
    this.description,
    this.logoUrl,
  });

  factory YieldStrategy.fromJson(Map<String, dynamic> j) => YieldStrategy(
        name: j['name'] as String,
        displayName: j['displayName'] as String,
        protocol: j['protocol'] as String,
        apr: (j['apr'] as num).toDouble(),
        riskLevel: j['riskLevel'] as String,
        minAmountUsdc: (j['minAmountUsdc'] as num).toDouble(),
        maxAmountUsdc: j['maxAmountUsdc'] != null ? (j['maxAmountUsdc'] as num).toDouble() : null,
        description: j['description'] as String?,
        logoUrl: j['logoUrl'] as String?,
      );
}

class VaultYieldInfo {
  final bool enabled;
  final String? strategy;
  final double apr;
  final double earnedUsdc;
  final double projectedUsdc;
  final double dailyEarnedUsdc;
  final bool autoCompound;
  final DateTime? lastCompoundAt;
  final int daysToMaturity;

  VaultYieldInfo({
    required this.enabled,
    this.strategy,
    this.apr = 0,
    this.earnedUsdc = 0,
    this.projectedUsdc = 0,
    this.dailyEarnedUsdc = 0,
    this.autoCompound = true,
    this.lastCompoundAt,
    this.daysToMaturity = 0,
  });

  factory VaultYieldInfo.fromJson(Map<String, dynamic> j) => VaultYieldInfo(
        enabled: j['enabled'] as bool? ?? false,
        strategy: j['strategy'] as String?,
        apr: (j['apr'] as num?)?.toDouble() ?? 0,
        earnedUsdc: (j['earnedUsdc'] as num?)?.toDouble() ?? 0,
        projectedUsdc: (j['projectedUsdc'] as num?)?.toDouble() ?? 0,
        dailyEarnedUsdc: (j['dailyEarnedUsdc'] as num?)?.toDouble() ?? 0,
        autoCompound: j['autoCompound'] as bool? ?? true,
        lastCompoundAt: j['lastCompoundAt'] != null ? DateTime.tryParse(j['lastCompoundAt']) : null,
        daysToMaturity: (j['daysToMaturity'] as num?)?.toInt() ?? 0,
      );
}

// ── Screen ──────────────────────────────────────────────────────────────────

class VaultYieldScreen extends ConsumerStatefulWidget {
  final Vault vault;
  const VaultYieldScreen({super.key, required this.vault});

  @override
  ConsumerState<VaultYieldScreen> createState() => _VaultYieldScreenState();
}

class _VaultYieldScreenState extends ConsumerState<VaultYieldScreen> {
  bool _busy = false;
  String? _selectedStrategy;

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final strategies = ref.watch(yieldStrategiesProvider);
    final yieldInfo = ref.watch(vaultYieldEarningsProvider(widget.vault.id));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.card,
        title: Text('DeFi Yield', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: colors.textPrimary),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Current yield status card ──
          _YieldStatusCard(vault: widget.vault, yieldInfo: yieldInfo, colors: colors),

          const SizedBox(height: 16),

          // ── Earnings breakdown ──
          if (widget.vault.yieldEnabled) ...[
            _EarningsBreakdown(yieldInfo: yieldInfo, vault: widget.vault, colors: colors),
            const SizedBox(height: 16),
          ],

          // ── Strategy picker ──
          if (!widget.vault.yieldEnabled) ...[
            Text('Choose a yield strategy',
                style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            strategies.when(
              data: (list) => Column(
                children: list.map((s) => _StrategyCard(
                  strategy: s,
                  selected: _selectedStrategy == s.name,
                  onTap: () => setState(() => _selectedStrategy = s.name),
                  colors: colors,
                )).toList(),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Text('Failed to load strategies', style: TextStyle(color: colors.danger)),
            ),
            if (_selectedStrategy != null) ...[
              const SizedBox(height: 24),
              _ActionButtons(
                busy: _busy,
                label: 'Enable Yield',
                icon: Icons.flash_on,
                colors: colors,
                onTap: () => _enableYield(colors),
              ),
            ],
          ] else ...[
            // ── Yield management buttons ──
            const SizedBox(height: 8),
            _ToggleRow(
              label: 'Auto-compound',
              value: widget.vault.yieldAutoCompound,
              colors: colors,
              onTap: () => _toggleAutoCompound(colors),
            ),
            const SizedBox(height: 12),
            _ActionButtons(
              busy: _busy,
              label: 'Compound Now',
              icon: Icons.sync,
              colors: colors,
              onTap: () => _compoundNow(colors),
            ),
            const SizedBox(height: 12),
            _ActionButtons(
              busy: _busy,
              label: 'Disable Yield',
              icon: Icons.power_settings_new,
              colors: colors,
              danger: true,
              onTap: () => _disableYield(colors),
            ),
          ],

          const SizedBox(height: 32),
          // ── Info section ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How DeFi Yield Works',
                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  'Your vault balance is supplied to the chosen DeFi protocol, which lends it to borrowers. '
                  'Interest earned is auto-compounded back into your vault daily. '
                  'You can withdraw at any time by breaking the vault (standard penalty applies).',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enableYield(AzamanColors colors) async {
    setState(() => _busy = true);
    try {
      final res = await apiClient.post('/vaults/${widget.vault.id}/yield/enable', {
        'strategy': _selectedStrategy,
      });
      if (res.statusCode != 200) {
        final msg = jsonDecode(res.body)['message'] ?? 'Failed to enable yield';
        throw Exception(msg);
      }
      ref.invalidate(vaultsProvider);
      ref.invalidate(vaultYieldEarningsProvider(widget.vault.id));
      ref.invalidate(vaultDetailProvider(widget.vault.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yield enabled!', style: TextStyle(color: Colors.white)),
              backgroundColor: colors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disableYield(AzamanColors colors) async {
    setState(() => _busy = true);
    try {
      await apiClient.post('/vaults/${widget.vault.id}/yield/disable', {});
      ref.invalidate(vaultsProvider);
      ref.invalidate(vaultYieldEarningsProvider(widget.vault.id));
      ref.invalidate(vaultDetailProvider(widget.vault.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yield disabled', style: TextStyle(color: Colors.white)),
              backgroundColor: colors.danger),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compoundNow(AzamanColors colors) async {
    setState(() => _busy = true);
    try {
      final res = await apiClient.post('/vaults/${widget.vault.id}/yield/compound', {});
      if (res.statusCode != 200) {
        final msg = jsonDecode(res.body)['message'] ?? 'Compounding failed';
        throw Exception(msg);
      }
      ref.invalidate(vaultsProvider);
      ref.invalidate(vaultYieldEarningsProvider(widget.vault.id));
      ref.invalidate(vaultDetailProvider(widget.vault.id));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final earned = (body['earned'] as num?)?.toDouble() ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(earned > 0 ? 'Compounded \$${earned.toStringAsFixed(2)}!' : 'No yield to compound yet',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: earned > 0 ? colors.success : colors.card,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAutoCompound(AzamanColors colors) async {
    setState(() => _busy = true);
    try {
      await apiClient.post('/vaults/${widget.vault.id}/yield/toggle-auto', {});
      ref.invalidate(vaultsProvider);
      ref.invalidate(vaultYieldEarningsProvider(widget.vault.id));
      ref.invalidate(vaultDetailProvider(widget.vault.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _YieldStatusCard extends StatelessWidget {
  final Vault vault;
  final AsyncValue<VaultYieldInfo> yieldInfo;
  final AzamanColors colors;

  const _YieldStatusCard({required this.vault, required this.yieldInfo, required this.colors});

  @override
  Widget build(BuildContext context) {
    final enabled = vault.yieldEnabled;
    final aprPct = (vault.yieldApr * 100).toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: enabled
              ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
              : [colors.card, colors.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: enabled ? Colors.green.shade300 : colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(enabled ? Icons.flash_on : Icons.flash_off,
                  color: enabled ? Colors.amber : colors.textSecondary, size: 28),
              const SizedBox(width: 8),
              Text(enabled ? 'Yield Active' : 'Yield Not Enabled',
                  style: TextStyle(
                    color: enabled ? Colors.white : colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _Stat(label: 'APR', value: '$aprPct%', color: Colors.white70),
                ),
                Expanded(child: _Stat(label: 'Earned', value: '\$${vault.yieldEarnedUsdc.toStringAsFixed(2)}', color: Colors.white70)),
                Expanded(child: _Stat(label: 'Strategy', value: vault.yieldStrategy ?? '—', color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 12),
            yieldInfo.when(
              data: (info) => Text(
                'Daily: \$${info.dailyEarnedUsdc.toStringAsFixed(4)} · Projected: \$${info.projectedUsdc.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              loading: () => const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => const SizedBox(),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text('Enable yield to earn interest on your vault balance.',
                style: TextStyle(color: colors.textSecondary, fontSize: 14)),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _EarningsBreakdown extends StatelessWidget {
  final AsyncValue<VaultYieldInfo> yieldInfo;
  final Vault vault;
  final AzamanColors colors;

  const _EarningsBreakdown({required this.yieldInfo, required this.vault, required this.colors});

  @override
  Widget build(BuildContext context) {
    return yieldInfo.when(
      data: (info) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yield Breakdown', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            _Row(colors: colors, label: 'Total earned', value: '\$${info.earnedUsdc.toStringAsFixed(4)}'),
            _Row(colors: colors, label: 'Daily earnings', value: '\$${info.dailyEarnedUsdc.toStringAsFixed(6)}'),
            _Row(colors: colors, label: 'Projected to maturity', value: '\$${info.projectedUsdc.toStringAsFixed(2)}'),
            _Row(colors: colors, label: 'Days to maturity', value: '${info.daysToMaturity}'),
            if (info.lastCompoundAt != null)
              _Row(colors: colors, label: 'Last compound', value: '${info.lastCompoundAt!.toLocal().toString().substring(0, 16)}'),
            const Divider(),
            _Row(colors: colors, label: 'Auto-compound', value: info.autoCompound ? 'ON' : 'OFF',
                valueColor: info.autoCompound ? colors.success : colors.textSecondary),
          ],
        ),
      ),
      loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox(),
    );
  }
}

class _StrategyCard extends StatelessWidget {
  final YieldStrategy strategy;
  final bool selected;
  final VoidCallback onTap;
  final AzamanColors colors;

  const _StrategyCard({required this.strategy, required this.selected, required this.onTap, required this.colors});

  @override
  Widget build(BuildContext context) {
    final riskColor = strategy.riskLevel == 'LOW'
        ? Colors.green
        : strategy.riskLevel == 'MEDIUM'
            ? Colors.orange
            : Colors.red;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colors.accent : colors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(strategy.displayName,
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(strategy.riskLevel,
                      style: TextStyle(color: riskColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${(strategy.apr * 100).toStringAsFixed(2)}% APR',
                    style: TextStyle(color: colors.accent, fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(width: 12),
                Text('Min \$${strategy.minAmountUsdc.toStringAsFixed(0)}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
            if (strategy.description != null) ...[
              const SizedBox(height: 8),
              Text(strategy.description!,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _ToggleRow({required this.label, required this.value, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
            const Spacer(),
            Switch(value: value, onChanged: (_) => onTap()),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final bool busy;
  final String label;
  final IconData icon;
  final AzamanColors colors;
  final VoidCallback onTap;
  final bool danger;

  const _ActionButtons({
    required this.busy,
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: busy ? null : onTap,
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: danger ? colors.danger : colors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final AzamanColors colors;
  const _Row({required this.label, required this.value, this.valueColor, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 14)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}

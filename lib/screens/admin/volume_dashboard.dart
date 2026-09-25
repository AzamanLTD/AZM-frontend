import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';


class VolumeDashboard extends ConsumerStatefulWidget {
  const VolumeDashboard({super.key});

  @override
  ConsumerState<VolumeDashboard> createState() => _VolumeDashboardState();
}

class _VolumeDashboardState extends ConsumerState<VolumeDashboard> {
  bool _isLoading = true;
  String? _error;

  // From /admin/stats
  double _fiatVolume24h = 0;
  double _totalFiatVolume = 0;
  double _cryptoVolume24h = 0;

  // From /admin/system-health
  double _hotWalletBalance = 0;
  double _masterCryptoBalance = 0;
  double _fiatPoolBalance = 0;
  double _profitFeesBalance = 0;
  double _totalSystemValue = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        apiClient.get('/admin/stats'),
        apiClient.get('/admin/system-health'),
      ]);

      final statsRes = results[0];
      final healthRes = results[1];

      if (statsRes.statusCode == 200) {
        final body = jsonDecode(statsRes.body);
        final stats = body['stats'] ?? {};
        _fiatVolume24h = _toDouble(stats['fiatVolume24h']);
        _totalFiatVolume = _toDouble(stats['totalFiatVolume']);
        _cryptoVolume24h = _toDouble(stats['cryptoVolume24h']);
      }

      if (healthRes.statusCode == 200) {
        final body = jsonDecode(healthRes.body);
        final pools = body['data']?['pools'] ?? {};
        _hotWalletBalance = _toDouble(pools['hotWallet']);
        _masterCryptoBalance = _toDouble(pools['masterCrypto']);
        _fiatPoolBalance = _toDouble(pools['fiatPool']);
        _profitFeesBalance = _toDouble(pools['profitFees']);
        _totalSystemValue = _toDouble(pools['totalSystemValue']);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _formatAmount(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.account_balance_outlined, color: colors.warning, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'VOLUME & RESERVES',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colors.textTertiary),
            onPressed: _fetchData,
          ),
        ],
      ),
      body: AzPullToRefresh(
        onRefresh: _fetchData,
        color: colors.accent,
        child: _buildBody(colors),
      ),
    );
  }

  Widget _buildBody(AzamanColors colors) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colors.accent),
            const SizedBox(height: 16),
            Text('Loading volume data...', style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          ],
        ),
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.cloud_outlined, size: 48, color: colors.danger),
          const SizedBox(height: 16),
          Text('Failed to load', textAlign: TextAlign.center,
              style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 12)),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: _fetchData,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: colors.accent, foregroundColor: Colors.black),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatsRow(colors),
        const SizedBox(height: 24),
        _buildSectionHeader('SYSTEM RESERVES', Icons.savings_outlined, colors),
        const SizedBox(height: 12),
        _buildReservesGrid(colors),
        const SizedBox(height: 24),
        _buildSectionHeader('RESERVE DISTRIBUTION', Icons.pie_chart_outline, colors),
        const SizedBox(height: 12),
        _buildDistributionBar(colors),
        const SizedBox(height: 24),
        _buildSectionHeader('TOTAL SYSTEM VALUE', Icons.diamond_outlined, colors),
        const SizedBox(height: 12),
        _buildTotalValueCard(colors),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildStatsRow(AzamanColors colors) {
    return Row(
      children: [
        Expanded(child: _statCard('24h Fiat Volume', 'GHS ${_formatAmount(_fiatVolume24h)}', Icons.analytics_outlined, colors.success, colors)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('24h Crypto', '\$${_formatAmount(_cryptoVolume24h)}', Icons.currency_bitcoin, colors.warning, colors)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('All-Time Fiat', 'GHS ${_formatAmount(_totalFiatVolume)}', Icons.calendar_today_outlined, colors.accent, colors)),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.8), size: 18),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 9), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, AzamanColors colors) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.textTertiary),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _buildReservesGrid(AzamanColors colors) {
    final reserves = [
      _ReserveEntry(label: 'Hot Wallet', value: _hotWalletBalance, color: colors.warning, icon: Icons.local_fire_department_outlined),
      _ReserveEntry(label: 'Master Crypto', value: _masterCryptoBalance, color: colors.accent, icon: Icons.ac_unit),
      _ReserveEntry(label: 'Fiat Pool', value: _fiatPoolBalance, color: colors.success, icon: Icons.account_balance_outlined),
      _ReserveEntry(label: 'Profit Fees', value: _profitFeesBalance, color: const Color(0xFF8B5CF6), icon: Icons.attach_money),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: reserves.map((r) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: r.color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: r.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(r.icon, color: r.color, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r.label,
                        style: TextStyle(color: colors.textTertiary, fontSize: 10, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('\$${_formatAmount(r.value)}',
                  style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDistributionBar(AzamanColors colors) {
    final total = _totalSystemValue > 0 ? _totalSystemValue : 1;
    final hotPct = (_hotWalletBalance / total * 100);
    final cryptoPct = (_masterCryptoBalance / total * 100);
    final fiatPct = (_fiatPoolBalance / total * 100);
    final profitPct = (_profitFeesBalance / total * 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 28,
              child: Row(
                children: [
                  if (hotPct > 0) Expanded(flex: hotPct.round().clamp(1, 100), child: Container(color: colors.warning.withValues(alpha: 0.7),
                      child: Center(child: Text('${hotPct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold))))),
                  if (cryptoPct > 0) Expanded(flex: cryptoPct.round().clamp(1, 100), child: Container(color: colors.accent.withValues(alpha: 0.6),
                      child: Center(child: Text('${cryptoPct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold))))),
                  if (fiatPct > 0) Expanded(flex: fiatPct.round().clamp(1, 100), child: Container(color: colors.success.withValues(alpha: 0.6),
                      child: Center(child: Text('${fiatPct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold))))),
                  if (profitPct > 0) Expanded(flex: profitPct.round().clamp(1, 100), child: Container(color: const Color(0xFF8B5CF6).withValues(alpha: 0.6),
                      child: Center(child: Text('${profitPct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold))))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _legendDot('Hot Wallet', colors.warning, colors),
              _legendDot('Crypto', colors.accent, colors),
              _legendDot('Fiat', colors.success, colors),
              _legendDot('Profit', const Color(0xFF8B5CF6), colors),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color color, AzamanColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 9)),
      ],
    );
  }

  Widget _buildTotalValueCard(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: colors.accent.withValues(alpha: 0.05), blurRadius: 20, spreadRadius: -4),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.diamond_outlined, color: colors.accent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total System Value', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                const SizedBox(height: 4),
                Text('\$${_formatAmount(_totalSystemValue)}',
                    style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReserveEntry {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  const _ReserveEntry({required this.label, required this.value, required this.color, required this.icon});
}

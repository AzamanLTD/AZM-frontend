import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/screens/admin/profit_dashboard.dart';
import 'package:azaman/screens/admin/users_dashboard.dart';
import 'package:azaman/screens/admin/volume_dashboard.dart';
import 'package:azaman/screens/admin_war_room_screen.dart';


class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});

  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}


class _AdminDashboardState extends ConsumerState<AdminDashboard>
    with SingleTickerProviderStateMixin {
  // ── State ─────────────────────────────────────────────────────────────────
  bool _isLoading = true;
  String? _error;

  Map<String, dynamic> _stats = {};
  Map<String, dynamic> _health = {};

  late AnimationController _radarController;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _fetchAll();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }


  // ── Data Fetching ─────────────────────────────────────────────────────────
  Future<void> _fetchAll() async {
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

      if (statsRes.statusCode != 200) {
        throw Exception('Stats API returned ${statsRes.statusCode}');
      }
      if (healthRes.statusCode != 200) {
        throw Exception('Health API returned ${healthRes.statusCode}');
      }


      final statsBody = jsonDecode(statsRes.body) as Map<String, dynamic>;
      final healthBody = jsonDecode(healthRes.body) as Map<String, dynamic>;

      if (statsBody['success'] != true) {
        throw Exception('Stats API success=false');
      }
      if (healthBody['success'] != true) {
        throw Exception('Health API success=false');
      }

      if (!mounted) return;
      setState(() {
        _stats = (statsBody['stats'] as Map<String, dynamic>?) ?? {};
        _health = (healthBody['data'] as Map<String, dynamic>?) ?? {};
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }


  // ── Number Formatting ─────────────────────────────────────────────────────
  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final num n = value is num ? value : num.tryParse(value.toString()) ?? 0;
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(2)}M';
    }
    if (n >= 1000) {
      final parts = n.toStringAsFixed(0).split('');
      final buffer = StringBuffer();
      for (int i = 0; i < parts.length; i++) {
        if (i > 0 && (parts.length - i) % 3 == 0) buffer.write(',');
        buffer.write(parts[i]);
      }
      return buffer.toString();
    }
    return n is int ? n.toString() : n.toStringAsFixed(2);
  }

  String _formatUsd(dynamic value) => '\$${_formatNumber(value)}';

  String _formatGhs(dynamic value) => 'GHS ${_formatNumber(value)}';


  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(colors),
      body: _buildBody(colors),
    );
  }

  PreferredSizeWidget _buildAppBar(AzamanColors colors) {
    return AppBar(
      backgroundColor: colors.surface,
      elevation: 0,
      title: Row(
        children: [
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _radarController.value * 6.28,
                child: child,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.radar, color: colors.accent, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'ADMIN COMMAND CENTER',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),

      actions: [
        IconButton(
          onPressed: _fetchAll,
          icon: Icon(Icons.refresh, color: colors.accent),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildBody(AzamanColors colors) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colors.accent),
            const SizedBox(height: 16),
            Text(
              'Loading command center...',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: colors.danger, size: 48),
              const SizedBox(height: 16),
              Text(
                'Failed to load data',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _fetchAll,
                icon: const Icon(Icons.refresh),
                label: const Text('RETRY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.background,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchAll,
      color: colors.accent,
      backgroundColor: colors.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatsGrid(colors),
          const SizedBox(height: 20),
          _buildSystemHealthSection(colors),
          const SizedBox(height: 20),
          _buildOracleSection(colors),
          const SizedBox(height: 20),
          _buildEngineSection(colors),
          const SizedBox(height: 20),
          _buildQuickStatsRow(colors),
          const SizedBox(height: 20),
          _buildWarRoomButton(colors),
          const SizedBox(height: 32),
        ],
      ),
    );
  }


  // ── Stats Grid (Top 3 Cards) ──────────────────────────────────────────────
  Widget _buildStatsGrid(AzamanColors colors) {
    return Row(
      children: [
        Expanded(
          child: _triumvirateCard(
            title: 'Profit\n(PnL)',
            value: _formatUsd(_stats['totalAdminProfit']),
            icon: Icons.analytics_outlined,
            accentColor: colors.accent,
            colors: colors,
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfitDashboard()),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _triumvirateCard(
            title: 'Total\nUsers',
            value: _formatNumber(_stats['totalUsers']),
            icon: Icons.group_outlined,
            accentColor: colors.success,
            colors: colors,
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UsersDashboard()),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _triumvirateCard(
            title: '24h\nVolume',
            value: _formatGhs(_stats['fiatVolume24h']),
            icon: Icons.account_balance_outlined,
            accentColor: colors.warning,
            colors: colors,

            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VolumeDashboard()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _triumvirateCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required AzamanColors colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.06),
              blurRadius: 20,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(height: 12),

            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Icon(Icons.arrow_forward, size: 10, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }


  // ── System Health Section ──────────────────────────────────────────────────
  Widget _buildSystemHealthSection(AzamanColors colors) {
    final pools = (_health['pools'] as Map<String, dynamic>?) ?? {};
    final totalSystem = _toDouble(pools['totalSystemValue']);

    return _sectionContainer(
      title: 'SYSTEM HEALTH',
      icon: Icons.favorite_outline,
      colors: colors,
      child: Column(
        children: [
          _poolBar(
            label: 'Master Crypto',
            value: _toDouble(pools['masterCrypto']),
            max: totalSystem,
            color: colors.accent,
            colors: colors,
          ),
          const SizedBox(height: 10),
          _poolBar(
            label: 'Hot Wallet',
            value: _toDouble(pools['hotWallet']),
            max: totalSystem,
            color: colors.success,
            colors: colors,
          ),
          const SizedBox(height: 10),
          _poolBar(
            label: 'Fiat Pool',
            value: _toDouble(pools['fiatPool']),
            max: totalSystem,
            color: colors.warning,
            colors: colors,
          ),
          const SizedBox(height: 10),
          _poolBar(
            label: 'Profit & Fees',
            value: _toDouble(pools['profitFees']),
            max: totalSystem,
            color: colors.danger,
            colors: colors,
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total System Value',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _formatUsd(totalSystem),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _poolBar({
    required String label,
    required double value,
    required double max,
    required Color color,
    required AzamanColors colors,
  }) {
    final fraction = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
            Text(
              _formatUsd(value),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: colors.divider,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }


  // ── Oracle Status Section ──────────────────────────────────────────────────
  Widget _buildOracleSection(AzamanColors colors) {
    final oracle = (_health['oracle'] as Map<String, dynamic>?) ?? {};
    final usdToGhs = _toDouble(oracle['liveUsdToGhs']);
    final retailRate = _toDouble(oracle['liveRetailRate']);
    final corpRate = _toDouble(oracle['liveCorporateRate']);
    final source = oracle['rateSource']?.toString() ?? 'N/A';
    final lastSync = oracle['lastRateSync']?.toString() ?? '';

    return _sectionContainer(
      title: 'ORACLE STATUS',
      icon: Icons.cloud_outlined,
      colors: colors,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _oracleRate('USD → GHS', usdToGhs.toStringAsFixed(2), colors),
              _oracleRate('Retail', retailRate.toStringAsFixed(2), colors),
              _oracleRate('Corporate', corpRate.toStringAsFixed(2), colors),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  source,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),

              Icon(Icons.access_time, size: 11, color: colors.textTertiary),
              const SizedBox(width: 4),
              Text(
                _formatTimestamp(lastSync),
                style: TextStyle(color: colors.textTertiary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _oracleRate(String label, String value, AzamanColors colors) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: colors.textTertiary, fontSize: 9),
        ),
      ],
    );
  }

  String _formatTimestamp(String raw) {
    if (raw.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(raw);
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return raw;
    }
  }


  // ── Engine Status Section ──────────────────────────────────────────────────
  Widget _buildEngineSection(AzamanColors colors) {
    final engine = (_health['engine'] as Map<String, dynamic>?) ?? {};
    final status = engine['status']?.toString() ?? 'unknown';
    final uptime = engine['uptime']?.toString() ?? 'N/A';
    final memory = engine['memoryUsage']?.toString() ?? 'N/A';
    final nodeVersion = engine['nodeVersion']?.toString() ?? 'N/A';
    final isOnline = status.toLowerCase() == 'online' ||
        status.toLowerCase() == 'running' ||
        status.toLowerCase() == 'healthy';

    return _sectionContainer(
      title: 'ENGINE STATUS',
      icon: Icons.memory_outlined,
      colors: colors,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isOnline ? colors.success : colors.danger)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (isOnline ? colors.success : colors.danger)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isOnline ? colors.success : colors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),

                    Text(
                      isOnline ? 'ONLINE' : status.toUpperCase(),
                      style: TextStyle(
                        color: isOnline ? colors.success : colors.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Node $nodeVersion',
                style: TextStyle(color: colors.textTertiary, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _engineMetric('Uptime', uptime, Icons.access_time, colors),
              const SizedBox(width: 16),
              _engineMetric(
                  'Memory', memory, Icons.sd_card_outlined, colors),
            ],
          ),
        ],
      ),
    );
  }

  Widget _engineMetric(
      String label, String value, IconData icon, AzamanColors colors) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.textTertiary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),

              Text(
                label,
                style: TextStyle(color: colors.textTertiary, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // ── Quick Stats Row ────────────────────────────────────────────────────────
  Widget _buildQuickStatsRow(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          _miniStat(
            'Active Trades',
            _formatNumber(_stats['liveTrades']),
            colors.success,
            colors,
          ),
          Container(width: 1, height: 32, color: colors.divider),
          _miniStat(
            'Disputes',
            _formatNumber(_stats['activeDisputes']),
            colors.danger,
            colors,
          ),
          Container(width: 1, height: 32, color: colors.divider),
          _miniStat(
            'Pending KYC',
            _formatNumber(_stats['pendingKyc']),
            colors.warning,
            colors,
          ),
          Container(width: 1, height: 32, color: colors.divider),
          _miniStat(
            'Withdrawals',
            _formatNumber(_stats['pendingWithdrawals']),
            colors.warning,
            colors,
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
      String label, String value, Color dotColor, AzamanColors colors) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textTertiary, fontSize: 9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // ── War Room Button ────────────────────────────────────────────────────────
  Widget _buildWarRoomButton(AzamanColors colors) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.heavyImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminWarRoomScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.danger.withValues(alpha: 0.8),
              colors.danger,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: colors.danger.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.military_tech_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            const Text(
              'OPEN WAR ROOM',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ── Shared Section Container ───────────────────────────────────────────────
  Widget _sectionContainer({
    required String title,
    required IconData icon,
    required AzamanColors colors,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: colors.textTertiary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

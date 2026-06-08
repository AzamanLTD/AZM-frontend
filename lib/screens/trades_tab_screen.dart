// =============================================================================
// TRADES TAB SCREEN — Active + Completed Trade History
//
// Two-section layout:
//   1. Active Trades (PENDING_PAYMENT, PAID, DISPUTED) — pulsing cards
//   2. Completed History (COMPLETED, CANCELLED) — clean list
//
// Features:
//   - Pull-to-refresh
//   - Empty states with helpful guidance
//   - Tappable cards navigate to ActiveTradeScreen
//   - Real-time updates via socket 'trade_update' events
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/active_trade_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class TradesTabScreen extends ConsumerStatefulWidget {
  const TradesTabScreen({super.key});

  @override
  ConsumerState<TradesTabScreen> createState() => _TradesTabScreenState();
}

class _TradesTabScreenState extends ConsumerState<TradesTabScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _activeTrades = [];
  List<Map<String, dynamic>> _completedTrades = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchTrades();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchTrades() async {
    try {
      final response = await apiClient.get('/trades/history');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List history = data['history'] ?? [];

        if (mounted) {
          setState(() {
            _activeTrades = history
                .where((t) => !['COMPLETED', 'CANCELLED', 'AUTO_CANCELLED'].contains(t['status']))
                .map<Map<String, dynamic>>((t) => Map<String, dynamic>.from(t))
                .toList();
            _completedTrades = history
                .where((t) => ['COMPLETED', 'CANCELLED', 'AUTO_CANCELLED'].contains(t['status']))
                .map<Map<String, dynamic>>((t) => Map<String, dynamic>.from(t))
                .toList();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[TradesTab] Fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: colors.accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: colors.accent,
            unselectedLabelColor: colors.textTertiary,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Active (${_activeTrades.length})'),
              Tab(text: 'History (${_completedTrades.length})'),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildActiveTab(colors),
              _buildHistoryTab(colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveTab(AzamanColors colors) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_activeTrades.isEmpty) {
      return _emptyState(colors, HugeIconsSolid.exchange01, 'No Active Trades',
          'Start a trade from the P2P marketplace to see it here.');
    }

    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _fetchTrades,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _activeTrades.length,
        itemBuilder: (context, index) => _buildTradeCard(_activeTrades[index], colors, isActive: true),
      ),
    );
  }

  Widget _buildHistoryTab(AzamanColors colors) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_completedTrades.isEmpty) {
      return _emptyState(colors, HugeIconsSolid.transactionHistory, 'No Trade History',
          'Completed and cancelled trades will appear here.');
    }

    return RefreshIndicator(
      color: colors.accent,
      onRefresh: _fetchTrades,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _completedTrades.length,
        itemBuilder: (context, index) => _buildTradeCard(_completedTrades[index], colors, isActive: false),
      ),
    );
  }

  Widget _buildTradeCard(Map<String, dynamic> trade, AzamanColors colors, {required bool isActive}) {
    final status = trade['status'] ?? 'UNKNOWN';
    final amountFiat = (trade['amountFiat'] as num?)?.toDouble() ?? 0;
    final amountCrypto = (trade['amountCrypto'] as num?)?.toDouble() ?? 0;
    final crypto = trade['crypto'] ?? 'USDT';
    final type = trade['type'] ?? 'SELL';
    final createdAt = trade['createdAt'] != null ? DateTime.tryParse(trade['createdAt'].toString()) : null;

    final statusColor = _getStatusColor(status, colors);
    final statusIcon = _getStatusIcon(status);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveTradeScreen(orderId: '#${trade['id']}'),
          ),
        ).then((_) => _fetchTrades());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? statusColor.withOpacity(0.3) : colors.divider,
            width: isActive ? 1.2 : 0.8,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: statusColor.withOpacity(0.08), blurRadius: 12)]
              : null,
        ),
        child: Row(
          children: [
            // Status icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(statusIcon, color: statusColor, size: 20),
            ),
            const SizedBox(width: 14),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${type == 'SELL' ? 'Buy' : 'Sell'} $crypto',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _formatStatus(status),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '\$${amountFiat.toStringAsFixed(2)} | ${amountCrypto.toStringAsFixed(4)} $crypto',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  if (createdAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _formatDate(createdAt),
                        style: TextStyle(color: colors.textTertiary, fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),

            Icon(HugeIconsSolid.arrowRight01, color: colors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(AzamanColors colors, IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: colors.textTertiary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: colors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: colors.textTertiary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status, AzamanColors colors) {
    switch (status) {
      case 'PENDING_PAYMENT': return colors.warning;
      case 'PAID': return colors.accent;
      case 'COMPLETED': return colors.success;
      case 'DISPUTED': return colors.danger;
      case 'CANCELLED':
      case 'AUTO_CANCELLED': return colors.textTertiary;
      default: return colors.textSecondary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'PENDING_PAYMENT': return HugeIconsSolid.hourglass;
      case 'PAID': return HugeIconsSolid.checkmarkCircle01;
      case 'COMPLETED': return HugeIconsSolid.checkmarkCircle01;
      case 'DISPUTED': return HugeIconsSolid.judge;
      case 'CANCELLED':
      case 'AUTO_CANCELLED': return HugeIconsSolid.cancel01;
      default: return HugeIconsSolid.exchange01;
    }
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'PENDING_PAYMENT': return 'AWAITING PAY';
      case 'AUTO_CANCELLED': return 'EXPIRED';
      default: return status;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}

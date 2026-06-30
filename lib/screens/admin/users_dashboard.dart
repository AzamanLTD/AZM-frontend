import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';


class UsersDashboard extends ConsumerStatefulWidget {
  const UsersDashboard({super.key});

  @override
  ConsumerState<UsersDashboard> createState() => _UsersDashboardState();
}

class _UsersDashboardState extends ConsumerState<UsersDashboard> {
  bool _isLoading = true;
  String? _error;

  // Stats from /admin/stats
  int _totalUsers = 0;
  int _activeVendors = 0;
  int _pendingKyc = 0;

  // Users from /admin/users
  List<dynamic> _users = [];

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
        apiClient.get('/admin/users?limit=20'),
      ]);

      final statsRes = results[0];
      final usersRes = results[1];

      if (statsRes.statusCode == 200) {
        final statsBody = jsonDecode(statsRes.body);
        final stats = statsBody['stats'] ?? {};
        _totalUsers = (stats['totalUsers'] as num?)?.toInt() ?? 0;
        _activeVendors = (stats['activeVendors'] as num?)?.toInt() ?? 0;
        _pendingKyc = (stats['pendingKyc'] as num?)?.toInt() ?? 0;
      }

      if (usersRes.statusCode == 200) {
        final usersBody = jsonDecode(usersRes.body);
        _users = usersBody['data']?['users'] ?? [];
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
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
                color: colors.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.group_outlined, color: colors.success, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'USERS',
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
      body: RefreshIndicator(
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
            Text('Loading users...', style: TextStyle(color: colors.textTertiary, fontSize: 13)),
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
        _buildSectionHeader('TOP USERS', Icons.emoji_events_outlined, colors),
        const SizedBox(height: 12),
        _buildUsersList(colors),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildStatsRow(AzamanColors colors) {
    return Row(
      children: [
        Expanded(child: _statCard('Total Users', _formatNum(_totalUsers), Icons.group_outlined, colors.success, colors)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Vendors', _formatNum(_activeVendors), Icons.storefront_outlined, colors.accent, colors)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Pending KYC', _formatNum(_pendingKyc), Icons.hourglass_empty, colors.warning, colors)),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.withOpacity(0.8), size: 18),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
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

  Widget _buildUsersList(AzamanColors colors) {
    if (_users.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
        child: Text('No users found', style: TextStyle(color: colors.textTertiary, fontSize: 13)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: List.generate(_users.length, (i) {
          final user = _users[i] as Map<String, dynamic>;
          final username = user['username'] ?? 'Unknown';
          final role = user['role'] ?? 'USER';
          final kycStatus = user['kycStatus'] ?? 'UNVERIFIED';
          final banStatus = user['banStatus'] ?? 'ACTIVE';
          final trades = user['tradesCompleted'] ?? 0;
          final strikes = user['strikeCount'] ?? 0;

          final roleColor = role == 'ADMIN'
              ? colors.danger
              : role == 'VENDOR'
                  ? colors.accent
                  : colors.textSecondary;

          final banColor = banStatus != 'ACTIVE' ? colors.danger : colors.success;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: i < _users.length - 1
                  ? Border(bottom: BorderSide(color: colors.divider))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                      style: TextStyle(color: roleColor, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(username,
                                style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: roleColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(role, style: TextStyle(color: roleColor, fontSize: 8, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$trades trades | KYC: $kycStatus${strikes > 0 ? ' | $strikes strikes' : ''}',
                        style: TextStyle(color: colors.textTertiary, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: banColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  String _formatNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

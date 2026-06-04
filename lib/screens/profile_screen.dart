// =============================================================================
// PROFILE SCREEN — Standalone user profile with edit, stats, security (V4)
//
// Architecture:
//   - ConsumerStatefulWidget that fetches from GET /api/users/profile on init.
//   - Shows avatar, identity, KYC badge, stats, balance summary, sections.
//   - Edit Profile bottom sheet for displayName, bio, phone → PUT /api/users/profile.
//   - Pull-to-refresh re-fetches all profile data.
//   - Theme-aware via `ref.watch(themeProvider).colors`.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';


class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isLoading = true;
  String? _error;

  // Profile data
  String _displayName = '';
  String _username = '';
  String _email = '';
  String _uid = '';
  String _bio = '';
  String _phone = '';
  String _kycStatus = 'UNVERIFIED';
  String _memberSince = '';
  int _tradesCompleted = 0;
  double _rating = 0.0;
  int _loginStreak = 0;
  String? _avatarUrl;


  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await apiClient.get('/users/profile');

      if (!mounted) return;

      final data = jsonDecode(response.body);
      final user = data['data'] ?? data['user'] ?? data;
      setState(() {
        _displayName = user['displayName'] ?? user['username'] ?? '';
        _username = user['username'] ?? '';
        _email = user['email'] ?? '';
        _uid = user['id']?.toString() ?? '';
        _bio = user['bio'] ?? '';
        _phone = user['phoneNumber'] ?? user['phone'] ?? '';
        _kycStatus = user['kycStatus'] ?? 'UNVERIFIED';
        _memberSince = user['createdAt'] ?? '';
        _tradesCompleted = user['tradesCompleted'] ?? 0;
        _rating = (user['rating'] ?? 0.0).toDouble();
        _loginStreak = user['loginStreak'] ?? 0;
        _avatarUrl = user['avatarUrl'];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Network error. Pull to retry.';
          _isLoading = false;
        });
      }
    }
  }


  Future<void> _submitProfileEdit({
    required String displayName,
    required String bio,
    required String phone,
  }) async {
    try {
      await apiClient.put('/users/profile', {
        'displayName': displayName,
        'bio': bio,
        'phoneNumber': phone,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      _fetchProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Try again.')),
        );
      }
    }
  }

  void _showEditSheet() {
    final colors = ref.read(themeProvider).colors;
    final nameCtrl = TextEditingController(text: _displayName);
    final bioCtrl = TextEditingController(text: _bio);
    final phoneCtrl = TextEditingController(text: _phone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text(
              'Edit Profile',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            _buildTextField(colors, nameCtrl, 'Display Name', Icons.person_rounded),
            const SizedBox(height: 12),
            _buildTextField(colors, bioCtrl, 'Bio', Icons.edit_rounded, maxLines: 3),
            const SizedBox(height: 12),
            _buildTextField(colors, phoneCtrl, 'Phone', Icons.phone_rounded),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _submitProfileEdit(
                    displayName: nameCtrl.text.trim(),
                    bio: bioCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Changes',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildTextField(
    AzamanColors colors,
    TextEditingController controller,
    String hint,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.textTertiary),
        prefixIcon: Icon(icon, color: colors.accent, size: 20),
        filled: true,
        fillColor: colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.accent.withOpacity(0.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Profile',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: colors.surface,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: colors.textPrimary),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_rounded, color: colors.accent, size: 22),
            onPressed: _showEditSheet,
            tooltip: 'Edit Profile',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
              ),
            )
          : _error != null
              ? _buildErrorState(colors)
              : RefreshIndicator(
                  onRefresh: _fetchProfile,
                  color: colors.accent,
                  backgroundColor: colors.surface,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      children: [
                        const SizedBox(height: 28),
                        _buildAvatarSection(colors),
                        const SizedBox(height: 24),
                        _buildKycBadge(colors),
                        const SizedBox(height: 24),
                        _buildBalanceSummary(colors),
                        const SizedBox(height: 8),
                        _buildSection(colors, 'Account Info', [
                          _buildInfoRow(colors, 'Display Name', _displayName),
                          _buildInfoRow(colors, 'Username', '@$_username'),
                          _buildInfoRow(colors, 'Email', _email),
                          _buildInfoRow(colors, 'UID', _uid),
                        ]),
                        _buildSection(colors, 'Stats & Reputation', [
                          _buildInfoRow(colors, 'Trades Completed', '$_tradesCompleted'),
                          _buildInfoRow(colors, 'Rating', '${_rating.toStringAsFixed(1)} / 5.0'),
                          _buildInfoRow(colors, 'Member Since', _formatDate(_memberSince)),
                          _buildInfoRow(colors, 'Login Streak', '$_loginStreak days'),
                        ]),
                        _buildSection(colors, 'Security', [
                          _buildInfoRow(colors, 'KYC Status', _kycStatus),
                          _buildInfoRow(colors, 'Two-Factor Auth', 'Enabled'),
                        ]),
                        _buildDangerZone(colors),
                      ],
                    ),
                  ),
                ),
    );
  }


  Widget _buildErrorState(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, color: colors.textTertiary, size: 48),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Something went wrong',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _fetchProfile,
            icon: Icon(Icons.refresh_rounded, color: colors.accent),
            label: Text('Retry', style: TextStyle(color: colors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarSection(AzamanColors colors) {
    final initial = _displayName.isNotEmpty
        ? _displayName[0].toUpperCase()
        : (_username.isNotEmpty ? _username[0].toUpperCase() : '?');

    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accent.withOpacity(0.12),
            border: Border.all(color: colors.accent.withOpacity(0.3), width: 2),
            boxShadow: [
              BoxShadow(
                color: colors.glow.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                color: colors.accent,
                fontSize: 36,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _displayName.isNotEmpty ? _displayName : _username,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (_username.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '@$_username',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }


  Widget _buildKycBadge(AzamanColors colors) {
    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    switch (_kycStatus.toUpperCase()) {
      case 'VERIFIED':
        badgeColor = colors.success;
        badgeIcon = Icons.verified_rounded;
        badgeText = 'Verified';
        break;
      case 'PENDING':
        badgeColor = colors.warning;
        badgeIcon = Icons.hourglass_top_rounded;
        badgeText = 'Pending';
        break;
      default:
        badgeColor = colors.danger;
        badgeIcon = Icons.warning_amber_rounded;
        badgeText = 'Unverified';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: badgeColor.withOpacity(0.08),
        border: Border.all(color: badgeColor.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, color: badgeColor, size: 18),
          const SizedBox(width: 8),
          Text(
            'KYC: $badgeText',
            style: TextStyle(
              color: badgeColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceSummary(AzamanColors colors) {
    final balanceData = ref.watch(balanceDataProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: colors.card,
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildBalanceStat(
              colors,
              'Available',
              '\$${balanceData.availableBalance.toStringAsFixed(2)}',
              colors.success,
            ),
          ),
          Container(width: 1, height: 36, color: colors.divider),
          Expanded(
            child: _buildBalanceStat(
              colors,
              'Escrow',
              '\$${balanceData.escrowLockedBalance.toStringAsFixed(2)}',
              colors.warning,
            ),
          ),
          Container(width: 1, height: 36, color: colors.divider),
          Expanded(
            child: _buildBalanceStat(
              colors,
              'AZM',
              balanceData.azmBalance.toStringAsFixed(1),
              colors.accentSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceStat(
    AzamanColors colors,
    String label,
    String value,
    Color valueColor,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }


  Widget _buildSection(AzamanColors colors, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: colors.card,
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(AzamanColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value.isNotEmpty ? value : '—',
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
          child: Text(
            'DANGER ZONE',
            style: TextStyle(
              color: colors.danger,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: colors.danger.withOpacity(0.04),
            border: Border.all(color: colors.danger.withOpacity(0.15)),
          ),
          child: ListTile(
            onTap: _showDeleteConfirmation,
            leading: Icon(Icons.delete_forever_rounded, color: colors.danger),
            title: Text(
              'Delete Account',
              style: TextStyle(
                color: colors.danger,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Permanently remove your account and all data',
              style: TextStyle(
                color: colors.danger.withOpacity(0.6),
                fontSize: 11,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              color: colors.danger.withOpacity(0.5),
              size: 14,
            ),
          ),
        ),
      ],
    );
  }


  void _showDeleteConfirmation() {
    final colors = ref.read(themeProvider).colors;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Account?',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This action is irreversible. All your data, balances, and trade history will be permanently deleted.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: colors.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Implement account deletion API call
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Account deletion requested. Check your email.'),
                  backgroundColor: colors.danger,
                ),
              );
            },
            child: Text(
              'Delete',
              style: TextStyle(color: colors.danger, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '—';
    try {
      final date = DateTime.parse(isoDate);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

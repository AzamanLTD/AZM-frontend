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
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/kyc_verification_screen.dart';
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
  String _azamanId = '';
  bool _isUploadingAvatar = false;
  final ImagePicker _picker = ImagePicker();


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
        _azamanId = user['azamanId']?.toString() ?? '';
        _bio = user['bio'] ?? '';
        _phone = user['phoneNumber'] ?? user['phone'] ?? '';
        _kycStatus = user['kycStatus'] ?? 'UNVERIFIED';
        _memberSince = user['createdAt'] ?? '';
        _tradesCompleted = user['tradesCompleted'] ?? 0;
        _rating = (user['rating'] ?? 0.0).toDouble();
        _loginStreak = user['loginStreak'] ?? 0;
        // NOTE: backend field is `profilePictureUrl`, not `avatarUrl` — the
        // old key here never matched a real response, which is why photos
        // never rendered on this screen.
        _avatarUrl = user['profilePictureUrl'] ?? user['avatarUrl'];
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

  Future<void> _pickAndUploadAvatar() async {
    final colors = ref.read(themeProvider).colors;
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked == null) return;

      HapticFeedback.lightImpact();
      setState(() => _isUploadingAvatar = true);

      // Build the multipart request against the full resolved URL,
      // then hand it to apiClient.multipart() which injects the auth header.
      final uri = Uri.parse('${ApiClient.baseUrl}/users/profile/avatar');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('avatar', picked.path,
            filename: 'avatar.jpg'),
      );

      final response = await apiClient.multipart('/users/profile/avatar', request);

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('Server returned unexpected response (${response.statusCode})');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final msg = data['message']?.toString() ?? 'Upload failed (${response.statusCode})';
        throw Exception(msg);
      }

      final newUrl = (data['data']?['profilePictureUrl'] ?? data['profilePictureUrl'])?.toString();

      if (!mounted) return;
      setState(() {
        if (newUrl != null && newUrl.isNotEmpty) _avatarUrl = newUrl;
        _isUploadingAvatar = false;
      });

      // Propagate to home header, settings drawer, etc.
      if (newUrl != null && newUrl.isNotEmpty) {
        ref.read(authProvider).updateProfilePicture(newUrl);
      }

      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated ✓')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update photo: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: colors.danger,
          ),
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
            _buildTextField(colors, nameCtrl, 'Display Name', Icons.person_outline),
            const SizedBox(height: 12),
            _buildTextField(colors, bioCtrl, 'Bio', Icons.edit_outlined, maxLines: 3),
            const SizedBox(height: 12),
            _buildTextField(colors, phoneCtrl, 'Phone', Icons.phone_outlined),
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
            icon: Icon(Icons.edit_outlined, color: colors.accent, size: 22),
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
                        _kycBanner(colors),
                        const SizedBox(height: 28),
                        _buildAvatarSection(colors),
                        const SizedBox(height: 24),
                        _buildKycBadge(colors),
                        const SizedBox(height: 24),
                        _buildSection(colors, 'Account Info', [
                          _buildInfoRow(colors, 'Display Name', _displayName),
                          _buildInfoRow(colors, 'Username', _username),
                          _buildInfoRow(colors, 'Email', _email),
                          _buildInfoRow(colors, 'AZM ID', _azamanId),
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
                        // Danger Zone / Delete Account lives at the bottom of
                        // the main Settings screen now (next to Sign Out) —
                        // one canonical place for it instead of two.
                      ],
                    ),
                  ),
                ),
    );
  }


  Widget _kycBanner(AzamanColors colors) {
    final status = _kycStatus.toUpperCase();
    final isVerified = status == "VERIFIED";
    final isPending  = status == "PENDING";
    final color = isVerified ? colors.success
      : isPending ? colors.warning : colors.danger;
    final icon = isVerified ? Icons.shield_outlined
      : isPending ? Icons.access_time : Icons.error_outline;
    final label = isVerified ? "KYC Verified"
      : isPending ? "KYC Pending Review"
      : "Verify Identity to Unlock Higher Limits";
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4), width: 1.2),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(label,
          style: TextStyle(color: color, fontSize: 13,
            fontWeight: FontWeight.w700))),
        if (!isVerified && !isPending)
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const KycVerificationScreen())),
            child: Text("Verify ->",
              style: TextStyle(color: color, fontSize: 12,
                fontWeight: FontWeight.w800)),
          ),
      ]),
    );
  }

  Widget _buildErrorState(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_outlined, color: colors.textTertiary, size: 48),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Something went wrong',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _fetchProfile,
            icon: Icon(Icons.refresh, color: colors.accent),
            label: Text('Retry', style: TextStyle(color: colors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _initialsAvatar(AzamanColors colors) {
    final initial = _displayName.isNotEmpty
        ? _displayName[0].toUpperCase()
        : (_username.isNotEmpty ? _username[0].toUpperCase() : 'A');
    return Container(
      width: 88, height: 88,
      color: colors.accent.withOpacity(0.15),
      child: Center(child: Text(initial, style: TextStyle(
        color: colors.accent, fontSize: 32,
        fontWeight: FontWeight.w800))),
    );
  }

  Widget _buildAvatarSection(AzamanColors colors) {
    return Column(
      children: [
        GestureDetector(
          onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: colors.card,
                child: ClipOval(
                  child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: _avatarUrl!,
                        width: 88, height: 88,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => CircularProgressIndicator(
                          strokeWidth: 2, color: colors.accent),
                        errorWidget: (_, __, ___) => _initialsAvatar(colors),
                      )
                    : _initialsAvatar(colors),
                ),
              ),
              if (_isUploadingAvatar)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.45),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent,
                    border: Border.all(color: colors.surface, width: 2.5),
                  ),
                  child: Icon(
                    Icons.camera_alt,
                    size: 14,
                    color: colors.isDark ? Colors.black : Colors.white,
                  ),
                ),
            ],
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
        badgeIcon = Icons.check_circle_outline;
        badgeText = 'Verified';
        break;
      case 'PENDING':
        badgeColor = colors.warning;
        badgeIcon = Icons.hourglass_empty;
        badgeText = 'Pending';
        break;
      default:
        badgeColor = colors.danger;
        badgeIcon = Icons.error_outline;
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

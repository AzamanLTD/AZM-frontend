// =============================================================================
// PROFILE DETAILS SCREEN — KYC-focused identity view (Phase P1 theme migration)
//
// Shows: avatar, legal name / username, UID, KYC status card, account info,
// social links, security level. Tappable KYC card navigates to KycVerificationScreen.
//
// Phase P1 (2026-05-25): migrated from hardcoded dark colors (0xFF0B0E11,
// 0xFF1E2329) to themeProvider — same fix as TradeSummaryScreen (PR #54).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

import 'package:azaman/screens/kyc_verification_screen.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class ProfileDetailsScreen extends ConsumerStatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  ConsumerState<ProfileDetailsScreen> createState() =>
      _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends ConsumerState<ProfileDetailsScreen> {
  String _kycStatus = "LOADING";
  String _legalName = "";

  @override
  void initState() {
    super.initState();
    _fetchKycStatus();
  }

  Future<void> _fetchKycStatus() async {
    try {
      final response = await apiClient.get('/kyc/status');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['kyc'];
        if (mounted) {
          setState(() {
            _kycStatus = data['kycStatus'] ?? "UNVERIFIED";
            _legalName = data['legalName'] ?? "";
          });
        }
      } else {
        if (mounted) setState(() => _kycStatus = "UNVERIFIED");
      }
    } catch (e) {
      if (mounted) setState(() => _kycStatus = "UNVERIFIED");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final authUser = ref.watch(authProvider).user;
    final String userEmail = authUser?.email ?? "Loading...";
    final String username = authUser?.username ?? "Loading...";
    final String userId = authUser?.id.toString() ?? "N/A";

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          "Profile",
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: colors.textPrimary),
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 40,
              backgroundColor: colors.card,
              child: Icon(HugeIconsSolid.user, size: 50, color: colors.textTertiary),
            ),
            const SizedBox(height: 12),
            Text(
              _legalName.isNotEmpty ? _legalName : username,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "UID: $userId",
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // --- DYNAMIC VERIFICATION CARD ---
            _buildDynamicVerificationCard(colors),

            // --- ACCOUNT INFO SECTION ---
            _sectionHeader("Account Information", colors),
            _buildInfoTile(
              colors,
              label: "Email",
              value: userEmail,
              trailing: IconButton(
                icon: Icon(HugeIconsSolid.copy01, color: colors.accent, size: 18),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Clipboard.setData(ClipboardData(text: userEmail));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text("Email copied to clipboard"),
                      duration: const Duration(seconds: 1),
                      backgroundColor: colors.surface,
                    ),
                  );
                },
              ),
            ),
            _buildInfoTile(
              colors,
              label: "Username",
              value: username,
            ),

            // --- SOCIAL LINKING ---
            _sectionHeader("Social Links", colors),
            _buildInfoTile(
              colors,
              label: "Twitter (X)",
              value: "@AzamanOfficial",
              trailing: Icon(HugeIconsSolid.link01, color: colors.accentSecondary, size: 20),
              onTap: () {
                // Future logic to open Twitter URL
              },
            ),

            // --- SECURITY LEVEL ---
            _sectionHeader("Security", colors),
            _buildInfoTile(
              colors,
              label: "Security Level",
              value: _kycStatus == "VERIFIED" ? "High" : "Standard",
              trailing: Icon(
                HugeIconsSolid.shield01,
                color: _kycStatus == "VERIFIED" ? colors.success : colors.accent,
                size: 20,
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // --- DYNAMIC KYC STATUS CARD ---
  Widget _buildDynamicVerificationCard(AzamanColors colors) {
    Color cardColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;
    bool isClickable = false;

    switch (_kycStatus) {
      case "LOADING":
        return Center(
          child: CircularProgressIndicator(
            color: colors.textTertiary,
          ),
        );

      case "VERIFIED":
        cardColor = colors.success;
        iconColor = colors.success;
        icon = HugeIconsSolid.checkmarkCircle01;
        title = "Identity Verified";
        subtitle = "Full access to Azaman features";
        isClickable = false;
        break;

      case "PENDING":
        cardColor = colors.warning;
        iconColor = colors.warning;
        icon = HugeIconsSolid.hourglass;
        title = "Verification Pending";
        subtitle = "Documents under review by Admin";
        isClickable = false;
        break;

      case "REJECTED":
        cardColor = colors.danger;
        iconColor = colors.danger;
        icon = HugeIconsSolid.alertCircle;
        title = "Verification Rejected";
        subtitle = "Tap here to re-submit your documents";
        isClickable = true;
        break;

      case "UNVERIFIED":
      default:
        cardColor = colors.accent;
        iconColor = colors.accent;
        icon = HugeIconsSolid.alertCircle;
        title = "Action Required";
        subtitle = "Tap here to verify your identity";
        isClickable = true;
        break;
    }

    return GestureDetector(
      onTap: () {
        if (isClickable) {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const KycVerificationScreen()),
          ).then((_) {
            _fetchKycStatus();
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cardColor.withOpacity(0.3)),
          boxShadow: isClickable
              ? [
                  BoxShadow(
                    color: cardColor.withOpacity(0.05),
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 30),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isClickable)
              Icon(
                HugeIconsSolid.arrowRight01,
                color: iconColor.withOpacity(0.7),
                size: 14,
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 25, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(
    AzamanColors colors, {
    required String label,
    required String value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        subtitle: Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: trailing,
      ),
    );
  }
}

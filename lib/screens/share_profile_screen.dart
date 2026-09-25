// =============================================================================
// AZAMAN — SHARE PROFILE QR CODE SCREEN
//
// Shows the user's Azaman username as a scannable QR code for easy friend
// adding. Also provides a copy-to-clipboard button and share link.
//
// Accessible from:
//   - Settings drawer → QR icon button (previously dead)
//   - Profile screen (future)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/widgets/animated_qr_dust.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/qr_scanner_screen.dart';
import 'package:azaman/widgets/nav_transitions.dart';


class ShareProfileScreen extends ConsumerWidget {
  const ShareProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final auth = ref.watch(authProvider);
    final username = auth.user?.username ?? 'unknown';
    final qrData = 'azaman://user/$username';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        title: Text(
          'Share Profile',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          pushWithVerticalTransition(context, const QrScannerScreen());
        },
        backgroundColor: colors.accent,
        foregroundColor: colors.isDark ? Colors.black : Colors.white,
        icon: const Icon(Icons.qr_code_outlined, size: 20),
        label: const Text('Scan', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar circle with initial
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.accent.withValues(alpha: 0.3), width: 2),
                ),
                child: Center(
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Username
              Text(
                '@$username',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Scan to add me on Azaman',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 32),

              // QR Code card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: colors.accent.withValues(alpha: 0.08),
                      blurRadius: 30,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: AnimatedQrDust(
                  data: qrData,
                  size: 220,
                  inkColor: const Color(0xFF1A1A2E),
                  backgroundColor: Colors.white,
                  errorCorrectLevel: 0, // QrErrorCorrectLevel.M = 0
                ),
              ),

              const SizedBox(height: 32),

              // Copy username button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: username));
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Username copied: @$username',
                          style: TextStyle(color: colors.textPrimary),
                        ),
                        backgroundColor: colors.card,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: Icon(Icons.copy_outlined, color: colors.accent, size: 18),
                  label: Text(
                    'Copy Username',
                    style: TextStyle(
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.accent.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Share link button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: 'Add me on Azaman P2P! My username: @$username\nhttps://azaman.me'));
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Share text copied to clipboard!',
                          style: TextStyle(color: colors.textPrimary),
                        ),
                        backgroundColor: colors.card,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text(
                    'Share Invite Link',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Hint
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.accent.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: colors.accent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Friends can scan this QR code or search your username to send you crypto instantly.',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

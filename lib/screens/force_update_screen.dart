import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:azaman/providers/theme_provider.dart';


// =============================================================================
// AZAMAN — FORCE UPDATE SCREEN (Phase Q15-FE)
//
// Blocking fullscreen overlay shown when the client version is below the
// backend's `versionGate.minVersion`. The user CANNOT dismiss or navigate
// away — the only action is tapping "Update Now" which opens the store URL.
// =============================================================================

class ForceUpdateScreen extends ConsumerWidget {
  final String message;
  final String? updateUrl;
  final String? minVersion;

  const ForceUpdateScreen({
    super.key,
    required this.message,
    this.updateUrl,
    this.minVersion,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return PopScope(
      canPop: false, // Block back button
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.download_outlined,
                    size: 60,
                    color: colors.accent,
                  ),
                ),

                const SizedBox(height: 40),

                // Title
                Text(
                  'Update Required',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                // Message from backend
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),

                if (minVersion != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Minimum version: $minVersion',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],

                const Spacer(flex: 2),

                // Update button
                if (updateUrl != null && updateUrl!.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => _openUpdateUrl(context, colors),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor:
                            colors.isDark ? Colors.black : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_outlined, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Update Now',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUpdateUrl(BuildContext context, AzamanColors colors) async {
    final uri = Uri.parse(updateUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open update link. Please visit your app store manually.',
              style: TextStyle(color: colors.textPrimary),
            ),
            backgroundColor: colors.card,
          ),
        );
      }
    }
  }
}

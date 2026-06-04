import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/providers/theme_provider.dart';

class AzamanStoreScreen extends ConsumerWidget {
  const AzamanStoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.accent, colors.accent.withOpacity(0.6)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              'AZAMAN STORE',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated store icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors.accent.withOpacity(0.2),
                      colors.accent.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  size: 56,
                  color: colors.accent,
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(begin: const Offset(1, 1), end: const Offset(1.08, 1.08), duration: 2000.ms)
                  .shimmer(duration: 3000.ms, color: colors.accent.withOpacity(0.3)),

              const SizedBox(height: 32),

              Text(
                'Coming Soon',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2),

              const SizedBox(height: 12),

              Text(
                'The Azaman Store is being crafted',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 600.ms),

              const SizedBox(height: 40),

              // What to expect
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WHAT TO EXPECT',
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _expectItem(Icons.auto_awesome, 'Profile Decorations', 'Unique rings, badges & card styles', colors),
                    const SizedBox(height: 12),
                    _expectItem(Icons.palette_outlined, 'Exclusive Themes', 'Premium color palettes & effects', colors),
                    const SizedBox(height: 12),
                    _expectItem(Icons.diamond_outlined, 'Vendor Flair', 'Stand out in the marketplace', colors),
                    const SizedBox(height: 12),
                    _expectItem(Icons.bolt_rounded, 'AZM Boosts', 'Power-ups for your trading experience', colors),
                    const SizedBox(height: 12),
                    _expectItem(Icons.card_giftcard_rounded, 'Gift Cards', 'Send store items to friends', colors),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms, duration: 600.ms).slideY(begin: 0.1),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.accent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_active_rounded, size: 14, color: colors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'You\'ll be notified when it launches',
                      style: TextStyle(color: colors.accent, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 600.ms, duration: 600.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expectItem(IconData icon, String title, String subtitle, dynamic colors) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: colors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(color: colors.textTertiary, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

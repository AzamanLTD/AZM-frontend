// =============================================================================
// THEMES SCREEN  (Home/Settings refresh §8, 2026-10-13)
//
// One destination for the whole identity/colour experience:
//   • Appearance — light / dark preview cards (dark stays the default).
//   • Accent identity — the full palette, LABELLED and with accessible
//     selected states, not colour-only discs (the old four-disc row lived
//     in sensory preferences; it belongs here).
//   • A live "accent in context" preview so the user sees the active
//     identity applied to real surfaces, icons, typography and buttons
//     before committing.
//
// Every choice applies immediately — ThemeProvider.setTheme / setAccent
// notify listeners synchronously and persist to SharedPreferences; no
// restart, no network round trip.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class ThemePickerScreen extends ConsumerWidget {
  const ThemePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(themeProvider);
    final activeColors = notifier.colors;
    final selected = notifier.currentTheme;
    final selectedCard = notifier.cardVariant;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: activeColors.textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Themes',
          style: TextStyle(
            color: activeColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Active summary — shows the live state immediately, so the user
          // can never wonder "which one am I on?".
          _ActiveSummary(
            colors: activeColors,
            label:
                '${activeColors.isDark ? 'Dark' : 'Light'} · '
                '${selectedCard.label} card',
          ),
          const SizedBox(height: 16),

          _GroupHeader('Appearance', colors: activeColors),
          ...AzamanTheme.values.asMap().entries.map((e) {
            final t = e.value;
            // Truthful preview: each appearance card shows the user's
            // CURRENT accent applied to that theme, not the historical
            // gold/teal identity, so what you see is what you'd get.
            // Truthful preview: the card's brand accent applied to that
            // appearance, computed exactly as the live shell computes it.
            final base = ThemeProvider.getColors(t);
            final c = base.withBrand(brandAccentFor(selectedCard, base.isDark));
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child:
                  _ThemePreviewCard(
                        theme: t,
                        colors: c,
                        isSelected: selected == t,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          AzamanHaptics.confirm();
                          ref.read(themeProvider).setTheme(t);
                        },
                      )
                      .animate()
                      .fadeIn(delay: (e.key * 80).ms, duration: 320.ms)
                      .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
            );
          }),

          _GroupHeader('Brand', colors: activeColors),
          _CardIdentitySummary(colors: activeColors, variant: selectedCard),

          const SizedBox(height: 16),
          _GroupHeader('Brand in context', colors: activeColors),
          _AccentContextPreview(colors: activeColors),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Your brand follows the ${selectedCard.label} balance card. '
              'Press and hold the card on Home to switch it, and the whole '
              'app changes with it. Appearance above applies instantly and '
              'is remembered across restarts.',
              style: TextStyle(
                color: activeColors.textTertiary,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small pieces ──────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final String title;
  final AzamanColors colors;

  const _GroupHeader(this.title, {required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
      child: Text(
        title,
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ActiveSummary extends StatelessWidget {
  final AzamanColors colors;
  final String label;

  const _ActiveSummary({required this.colors, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('themes_active_summary'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider, width: 0.6),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, color: colors.accent, size: 18),
          const SizedBox(width: 10),
          Text(
            'Active: ',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          // FLEXIBLE: the label now names BOTH the appearance and the card
          // identity ("Dark · Green card"), which is wider than the old
          // accent name. It must ellipsize rather than overflow the pill at
          // 320dp or at large text scales.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.circle, color: colors.accent, size: 8, fill: 1.0),
        ],
      ),
    );
  }
}

/// The brand identity summary. There is NO accent picker any more: the
/// applied balance card owns the accent, so this states the current identity
/// and points at the one place it can be changed (the card itself).
class _CardIdentitySummary extends StatelessWidget {
  final AzamanColors colors;
  final BalanceCardVariant variant;

  const _CardIdentitySummary({required this.colors, required this.variant});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('themes_card_identity'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider, width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 22,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  kCardPalettes[variant]!.bright,
                  kCardPalettes[variant]!.mid,
                  kCardPalettes[variant]!.deep,
                ],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${variant.label} card · your app accent',
              key: const ValueKey('themes_card_identity_label'),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(Icons.touch_app, color: colors.textTertiary, size: 16),
        ],
      ),
    );
  }
}

class _AccentContextPreview extends StatelessWidget {
  final AzamanColors colors;

  const _AccentContextPreview({required this.colors});

  @override
  Widget build(BuildContext context) {
    final onAccent = colors.isDark ? Colors.black : Colors.white;
    return Container(
      key: const ValueKey('themes_context_preview'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: colors.accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wallet balance',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '1,284.50 USDC',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.accent, colors.accentSecondary],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Primary action',
                  style: TextStyle(
                    color: onAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colors.accentSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'Secondary',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Appearance preview cards ───────────────────────────────────────────────

class _ThemePreviewCard extends StatelessWidget {
  final AzamanTheme theme;
  final AzamanColors colors;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemePreviewCard({
    required this.theme,
    required this.colors,
    required this.isSelected,
    required this.onTap,
  });

  String _description() => switch (theme) {
    AzamanTheme.light => 'Clean white surfaces with deep navy text.',
    AzamanTheme.dark =>
      'True black. Easiest on the eyes at night. The Azaman default.',
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 160,
        decoration: BoxDecoration(
          color: colors.background,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.background,
              Color.alphaBlend(
                colors.accent.withValues(alpha: colors.isDark ? 0.10 : 0.05),
                colors.background,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colors.accent
                : Colors.white.withValues(alpha: colors.isDark ? 0.06 : 0.0),
            width: isSelected ? 2.0 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.30),
                    blurRadius: 22,
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // Halo
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.85, -0.95),
                      radius: 1.4,
                      colors: [
                        colors.glow.withValues(
                          alpha: colors.isDark ? 0.18 : 0.10,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          colors.icon,
                          color: colors.accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              theme == AzamanTheme.light ? 'Light' : 'Dark',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _description(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                          key: ValueKey(isSelected),
                          color: isSelected
                              ? colors.accent
                              : colors.textTertiary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Mini-mockup row — card surface + button + accent bar
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.divider, width: 0.6),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.success,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Card',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'CTA',
                          style: TextStyle(
                            color: colors.isDark ? Colors.black : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colors.accent, colors.accentSecondary],
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

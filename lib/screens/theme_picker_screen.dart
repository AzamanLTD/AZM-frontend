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
import 'package:azaman/utils/azaman_haptics.dart';

class ThemePickerScreen extends ConsumerWidget {
  const ThemePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(themeProvider);
    final activeColors = notifier.colors;
    final selected = notifier.currentTheme;
    final selectedAccent = notifier.accent;

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
                '${selectedAccent.label}',
          ),
          const SizedBox(height: 16),

          _GroupHeader('Appearance', colors: activeColors),
          ...AzamanTheme.values.asMap().entries.map((e) {
            final t = e.value;
            // Truthful preview: each appearance card shows the user's
            // CURRENT accent applied to that theme, not the historical
            // gold/teal identity, so what you see is what you'd get.
            final c = ThemeProvider.getColors(t).withAccent(selectedAccent);
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

          _GroupHeader('Accent', colors: activeColors),
          _AccentPalette(colors: activeColors),

          const SizedBox(height: 16),
          _GroupHeader('Accent in context', colors: activeColors),
          _AccentContextPreview(colors: activeColors),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'This is how ${selectedAccent.label} looks on your current '
              'surfaces right now. Every choice above applies instantly and '
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
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Icon(Icons.circle, color: colors.accent, size: 8, fill: 1.0),
        ],
      ),
    );
  }
}

/// The full accent palette. Every swatch carries a LABEL and a semantic
/// selected state — identity is never communicated by colour alone.
class _AccentPalette extends ConsumerWidget {
  final AzamanColors colors;

  const _AccentPalette({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeProvider.select((t) => t.accent));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider, width: 0.6),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        children: [
          for (final a in AzAccent.values)
            _AccentSwatch(
              accent: a,
              isSelected: current == a,
              colors: colors,
              onTap: () {
                ref.read(themeProvider).setAccent(a);
                AzamanHaptics.selection();
              },
            ),
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  final AzAccent accent;
  final bool isSelected;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _AccentSwatch({
    required this.accent,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = AzAccentFamily.all[accent]!.accentFor(colors.isDark);
    return Semantics(
      label:
          'Accent ${accent.label}'
          '${isSelected ? ', selected' : ''}',
      selected: isSelected,
      button: true,
      child: GestureDetector(
        key: ValueKey('accent_swatch_${accent.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [swatch, swatch.darken10()],
                  ),
                  border: Border.all(
                    color: isSelected ? colors.textPrimary : colors.border,
                    width: isSelected ? 2.5 : 0.5,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        color: AzAccentFamily.all[accent]!.onAccentFor(
                          colors.isDark,
                        ),
                        size: 18,
                      )
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                accent.label,
                style: TextStyle(
                  color: isSelected ? colors.textPrimary : colors.textTertiary,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature of the real app: card surface, icon, headline + body text,
/// filled button and an outline chip — rendered with the ACTIVE colours so
/// the user previews the identity on actual surfaces, not an abstract swatch.
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

// ── Colour helper ─────────────────────────────────────────────────────────
//
// A modest luminance-preserving shade for the swatch gradient so the disc
// reads as a lit sphere, not a flat sticker. Kept local: it is presentation
// sugar for one gradient stop.
extension _SwatchShade on Color {
  Color darken10() =>
      withValues(alpha: a, red: r * 0.82, green: g * 0.82, blue: b * 0.82);
}

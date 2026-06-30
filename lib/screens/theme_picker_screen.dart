// =============================================================================
// THEME PICKER SCREEN  (Master Sprint v2, 2026-05-27)
//
// Three explicit themes only — light, dark, midnight. Each renders as a
// generous preview card showing the actual gradient halo, accent colour,
// card surface and typography sample so users see what they're picking.
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: activeColors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Theme',
          style: TextStyle(
              color: activeColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: AzamanTheme.values.asMap().entries.map((e) {
          final t = e.value;
          final c = ThemeProvider.getColors(t);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ThemePreviewCard(
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
        }).toList(),
      ),
    );
  }
}

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
        AzamanTheme.light => 'Clean white surface with deep navy text and gold accent.',
        AzamanTheme.dark => 'The signature Azaman dark UI. Default.',
        AzamanTheme.midnight => 'Pitch black with violet accent. Easiest on the eyes at night.',
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
                colors.accent.withOpacity(colors.isDark ? 0.10 : 0.05),
                colors.background,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colors.accent
                : Colors.white.withOpacity(colors.isDark ? 0.06 : 0.0),
            width: isSelected ? 2.0 : 0.8,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colors.accent.withOpacity(0.30),
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
                        colors.glow.withOpacity(colors.isDark ? 0.18 : 0.10),
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
                          color: colors.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(colors.icon, color: colors.accent, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              colors.name,
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
                            horizontal: 10, vertical: 6),
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
                            horizontal: 10, vertical: 6),
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
                          gradient: LinearGradient(colors: [
                            colors.accent,
                            colors.accentSecondary,
                          ]),
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

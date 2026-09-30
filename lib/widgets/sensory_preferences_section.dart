// =============================================================================
// SENSORY PREFERENCES SECTION  (TASK-026)
//
// Haptics, sound, "success sounds only", ambient motion, and a tri-state
// reduce-motion control. Level-2 surface on purpose: settings must read as a
// form, not compete with the screen's one hero (assessment §1.3).
//
// Every toggle is a plain M3 Switch styled from AzamanColors. No dialogs.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/sensory_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class SensoryPreferencesSection extends ConsumerWidget {
  /// Optional heading override (e.g. "Feel" inside the Settings drawer).
  final String title;

  const SensoryPreferencesSection({super.key, this.title = 'Feel'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final p = ref.watch(sensoryProvider).prefs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border, width: 0.5),
          ),
          child: Column(
            children: [
              _SensoryRow(
                colors: colors,
                title: 'Haptics',
                subtitle: 'A short tap when something responds',
                value: p.hapticsEnabled,
                onChanged: (v) {
                  ref.read(sensoryProvider).setHapticsEnabled(v);
                  // Fire the acknowledgement AFTER the gate is updated, so
                  // turning haptics on acknowledges itself and turning them off
                  // is silent (the gate is already closed).
                  if (v) AzamanHaptics.toggle();
                },
              ),
              _divider(colors),
              _SensoryRow(
                colors: colors,
                title: 'Sound effects',
                subtitle: 'Success, money received, ticket events',
                value: p.soundEnabled,
                onChanged: (v) => ref.read(sensoryProvider).setSoundEnabled(v),
              ),
              _divider(colors),
              _SensoryRow(
                colors: colors,
                title: 'Success sounds only',
                subtitle: 'Silence the interface tick and the transition whoosh',
                value: p.soundSuccessOnly,
                enabled: p.soundEnabled,
                onChanged: (v) => ref.read(sensoryProvider).setSoundSuccessOnly(v),
              ),
              _divider(colors),
              _SensoryRow(
                colors: colors,
                title: 'Ambient motion',
                subtitle: 'The slow sheen drift on your balance card when idle',
                value: p.ambientMotionEnabled,
                onChanged: (v) => ref.read(sensoryProvider).setAmbientMotionEnabled(v),
              ),
              _divider(colors),
              _ReduceMotionRow(colors: colors, prefs: p, ref: ref),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider(AzamanColors colors) => Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Divider(height: 1, thickness: 0.5, color: colors.divider),
      );
}

class _SensoryRow extends StatelessWidget {
  final AzamanColors colors;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SensoryRow({
    required this.colors,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12,
                        height: 1.35,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: colors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReduceMotionRow extends StatelessWidget {
  final AzamanColors colors;
  final SensoryPreferences prefs;
  final WidgetRef ref;

  const _ReduceMotionRow({
    required this.colors,
    required this.prefs,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    //   null  → "follow my phone": the OS reduce-motion setting wins.
    //   true  → always reduce (a user who finds motion uncomfortable).
    //   false → always full motion (a user whose OS flag is on for battery).
    final bool? selected = prefs.forceReduceMotion;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reduce motion',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 2),
          Text('Follows your phone by default. Override it if you prefer.',
              style: TextStyle(color: colors.textTertiary, fontSize: 12, height: 1.35)),
          const SizedBox(height: 10),
          Row(
            children: [
              _Segment(
                colors: colors,
                label: 'Follow phone',
                active: selected == null,
                onTap: () {
                  ref.read(sensoryProvider).setForceReduceMotion(null);
                  AzamanHaptics.selection();
                },
              ),
              const SizedBox(width: 8),
              _Segment(
                colors: colors,
                label: 'Always',
                active: selected == true,
                onTap: () {
                  ref.read(sensoryProvider).setForceReduceMotion(true);
                  AzamanHaptics.selection();
                },
              ),
              const SizedBox(width: 8),
              _Segment(
                colors: colors,
                label: 'Never',
                active: selected == false,
                onTap: () {
                  ref.read(sensoryProvider).setForceReduceMotion(false);
                  AzamanHaptics.selection();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final AzamanColors colors;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Segment({
    required this.colors,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: MotionTokens.control,
        curve: MotionTokens.symmetric,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? colors.accent.withValues(alpha: 0.14) : colors.softSurface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: active ? colors.accent.withValues(alpha: 0.55) : colors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? colors.accent : colors.textSecondary,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

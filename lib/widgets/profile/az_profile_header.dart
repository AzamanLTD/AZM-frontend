// lib/widgets/profile/az_profile_header.dart
// =============================================================================
// THE PROFILE HEADER — one layout for you and for the people you look up.
//
//   ┌──────────────────────────────────────┐
//   │ ◯ back              sky band     ◯ ⋯ │   each person gets their own sky,
//   │                                      │   chosen from their id (stable)
//   └────────────────(  photo  )───────────┘
//                  Kofi Mensah ✓
//                     @kofi
//           [ Friends since Mar 2026 ] [ Verified ]
//             12 Completed | 4.8 Rating | 3 Mutual
//        (   Send   ) (  Message  ) ( ⋯ )
//
// The actions change between your own profile (Edit, QR) and someone else's
// (Send, Message, more); the shape does not.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/money_stage/money_stage.dart';

@immutable
class AzProfileChip {
  const AzProfileChip({required this.label, this.icon, this.tone});
  final String label;
  final IconData? icon;

  /// Optional colour for a status chip (e.g. verified green).
  final Color? tone;
}

@immutable
class AzProfileStat {
  const AzProfileStat({required this.value, required this.label, this.onTap});
  final String value;
  final String label;
  final VoidCallback? onTap;
}

@immutable
class AzProfileAction {
  const AzProfileAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// The one solid ink action (Send on someone else's profile).
  final bool primary;
  final Key? key;
}

/// The sky a person's profile wears: stable per person, from their id.
AzMoneyMood profileSkyFor(int seed) {
  const skies = [
    AzMoneyMood.send,
    AzMoneyMood.receive,
    AzMoneyMood.addMoney,
    AzMoneyMood.withdraw,
    AzMoneyMood.request,
    AzMoneyMood.pay,
    AzMoneyMood.convert,
  ];
  return skies[seed.abs() % skies.length];
}

class AzProfileHeader extends ConsumerWidget {
  const AzProfileHeader({
    super.key,
    required this.name,
    required this.seed,
    this.handle,
    this.avatarUrl,
    this.verified = false,
    this.verifiedTooltip = 'Verified',
    this.subtitle,
    this.chips = const [],
    this.stats = const [],
    this.actions = const [],
    this.onBack,
    this.trailing,
    this.onAvatarTap,
    this.skyPhase = 0.3,
  });

  final String name;

  /// Picks the sky (use the person's user id).
  final int seed;
  final String? handle;
  final String? avatarUrl;
  final bool verified;
  final String verifiedTooltip;
  final String? subtitle;
  final List<AzProfileChip> chips;
  final List<AzProfileStat> stats;
  final List<AzProfileAction> actions;
  final VoidCallback? onBack;

  /// Top-right control on the sky (e.g. a more menu or QR).
  final Widget? trailing;
  final VoidCallback? onAvatarTap;
  final double skyPhase;

  static const double bandHeight = 132;
  static const double avatarSize = 104;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final topInset = MediaQuery.paddingOf(context).top;
    final band = bandHeight + topInset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: band + avatarSize / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The sky, fading into the page.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: band,
                child: AzStageSkin(
                  mood: profileSkyFor(seed),
                  palette: AzSkyPalette.of(profileSkyFor(seed), Theme.of(context).brightness),
                  brightness: Theme.of(context).brightness,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // The sky itself fades to nothing at the bottom (a
                      // mask, not an overlay), so it melts into whatever
                      // page sits under it with no seam.
                      ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.0, 0.5, 1.0],
                          colors: [Colors.white, Colors.white, Colors.transparent],
                        ).createShader(rect),
                        child: AzAmbientBackdrop(mood: profileSkyFor(seed), phase: skyPhase),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 0),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Row(
                            children: [
                              if (onBack != null)
                                AzStageRoundButton(
                                  key: const ValueKey('profile-back'),
                                  icon: Icons.arrow_back_rounded,
                                  onTap: onBack,
                                  semanticsLabel: 'Back',
                                ),
                              const Spacer(),
                              if (trailing != null) trailing!,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // The photo, overlapping the sky's lower edge.
              Positioned(
                top: band - avatarSize / 2,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: onAvatarTap,
                    child: Container(
                      key: const ValueKey('profile-avatar'),
                      width: avatarSize,
                      height: avatarSize,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.background),
                      child: ClipOval(child: _photo(colors)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Name, verified mark, handle.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  key: const ValueKey('profile-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (verified) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: verifiedTooltip,
                  child: Icon(Icons.verified_rounded, size: 20, color: colors.accent),
                ),
              ],
            ],
          ),
        ),
        if (handle != null && handle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            handle!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 15),
          ),
        ],
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textPrimary, fontSize: 14, height: 1.35),
            ),
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [for (final c in chips) _chip(c, colors)],
            ),
          ),
        ],
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 16),
          _statsRow(colors),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  // A trailing icon-only action (more) stays square.
                  if (actions[i].label.isEmpty)
                    _action(actions[i], colors)
                  else
                    Expanded(child: _action(actions[i], colors)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _photo(AzamanColors colors) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final monogram = Container(
      color: colors.softSurface,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(color: colors.textPrimary, fontSize: 40, fontWeight: FontWeight.w700),
      ),
    );
    final url = avatarUrl;
    if (url == null || url.isEmpty) return monogram;
    return AzamanNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => monogram,
    );
  }

  Widget _chip(AzProfileChip c, AzamanColors colors) {
    final tone = c.tone ?? colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: c.tone?.withValues(alpha: 0.10) ?? colors.softSurface,
        border: Border.all(color: (c.tone ?? colors.textTertiary).withValues(alpha: 0.18), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.icon != null) ...[
            Icon(c.icon, size: 14, color: tone),
            const SizedBox(width: 5),
          ],
          Text(c.label, style: TextStyle(color: tone, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _statsRow(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 0.8, color: colors.divider),
              Expanded(
                child: InkWell(
                  onTap: stats[i].onTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Text(
                          stats[i].value,
                          style: AzText.money(colors.textPrimary, size: 18, weight: FontWeight.w700, tracking: -0.3),
                        ),
                        const SizedBox(height: 2),
                        Text(stats[i].label, style: TextStyle(color: colors.textSecondary, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action(AzProfileAction a, AzamanColors colors) {
    final fill = a.primary ? colors.textPrimary : colors.softSurface;
    final ink = a.primary ? colors.background : colors.textPrimary;
    return Semantics(
      button: true,
      label: a.label.isEmpty ? null : a.label,
      child: Material(
        key: a.key,
        color: fill,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: a.onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 46,
            width: a.label.isEmpty ? 46 : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(a.icon, size: 19, color: ink),
                if (a.label.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(a.label, style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Store action row (Overhaul 03 §1.2): primary intent · save · share · follow.
///
/// Save is bound to the durable server-bookmark seam (demo keeps the
/// device-local wishlist); share and follow
/// are *callbacks* into the storefront shell, which already owns follow state
/// (`isFollowing` is a shell input) — this row never introduces a second
/// source of truth. No "Storefront" button lives here (brief §5.5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/marketplace/experience/marketplace_experience_capabilities.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/server_bookmarks_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class StoreActionRow extends ConsumerWidget {
  final BusinessProfile business;
  final VoidCallback? onPrimary;
  final VoidCallback? onShare;
  final VoidCallback? onToggleFollow;
  final bool isFollowing;

  const StoreActionRow({
    super.key,
    required this.business,
    required this.onPrimary,
    this.onShare,
    this.onToggleFollow,
    this.isFollowing = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final label = MarketplaceExperienceCatalog.fromCategory(
      business.category,
    ).primaryActionLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AzSpace.xl, 0, AzSpace.xl, AzSpace.md),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              key: const ValueKey('store_primary_action'),
              onPressed: onPrimary == null
                  ? null
                  : () {
                      AzamanHaptics.nav();
                      onPrimary!();
                    },
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AzRadius.pill),
                ),
                padding: const EdgeInsets.symmetric(vertical: AzSpace.md),
              ),
              child: Text(label, style: AzText.button),
            ),
          ),
          const SizedBox(width: AzSpace.sm),
          StoreBookmarkToggle(business: business),
          if (onShare != null) ...[
            const SizedBox(width: AzSpace.xs),
            _RoundIcon(
              key: const ValueKey('store_share'),
              icon: HugeIconsSolid.share08,
              tooltip: 'Share',
              colors: colors,
              onTap: onShare!,
            ),
          ],
          if (onToggleFollow != null) ...[
            const SizedBox(width: AzSpace.xs),
            _RoundIcon(
              key: ValueKey('store_follow_${isFollowing ? 'on' : 'off'}'),
              icon: isFollowing
                  ? HugeIconsSolid.userCheck01
                  : HugeIconsSolid.userAdd01,
              tooltip: isFollowing ? 'Following' : 'Follow',
              active: isFollowing,
              colors: colors,
              onTap: onToggleFollow!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Bookmark bound to the durable server-bookmark seam
/// (`isBusinessSaved`/`toggleBusinessSaved`); demo mode keeps the
/// device-local wishlist.
class StoreBookmarkToggle extends ConsumerWidget {
  final BusinessProfile business;

  const StoreBookmarkToggle({super.key, required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final saved = isBusinessSaved(ref, business);
    return _RoundIcon(
      key: ValueKey('store_bookmark_${saved ? 'on' : 'off'}'),
      icon: saved ? HugeIconsSolid.bookmark02 : HugeIconsSolid.bookmark01,
      tooltip: saved ? 'Saved' : 'Save',
      active: saved,
      colors: colors,
      onTap: () {
        AzamanHaptics.toggle();
        toggleBusinessSaved(context, ref, business);
      },
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _RoundIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? colors.accentSurface : colors.softSurface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: active ? colors.accent : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

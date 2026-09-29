// =============================================================================
// FLOATING CART BAR — marketplace tray
//
// A persistent, tactile checkout surface shared by restaurant and retail
// experiences. The cart provider remains the sole source of truth; this widget
// only presents changes in a deliberate, reversible way.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

class FloatingCartBar extends ConsumerStatefulWidget {
  /// Called when the tray is opened.
  final VoidCallback onTap;

  /// Customer-facing name for the current category's tray.
  final String label;

  const FloatingCartBar({
    super.key,
    required this.onTap,
    this.label = 'View Cart',
  });

  @override
  ConsumerState<FloatingCartBar> createState() => _FloatingCartBarState();
}

class _FloatingCartBarState extends ConsumerState<FloatingCartBar>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _catch;
  late final Animation<double> _catchScale;
  bool _hasPresented = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    _catch = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _catchScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.92), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.07), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 1.0), weight: 15),
    ]).chain(CurveTween(curve: Curves.easeOut)).animate(_catch);
    ref.listenManual<CartState>(cartProvider, (previous, next) {
      if (previous == null) return;
      final countChanged = previous.itemCount != next.itemCount;
      final subtotalChanged = previous.subtotal != next.subtotal;
      if (countChanged || subtotalChanged) {
        if (next.itemCount > 0 && !_hasPresented && mounted) {
          setState(() => _hasPresented = true);
        }
        // The OS accessibility setting gates the celebration: under reduced
        // motion nothing animates — the bar settles straight to its new
        // state (MotionTokens.accessibleDuration is the canonical gate for
        // the tween-based transitions further below).
        final reduceMotion = mounted && MediaQuery.disableAnimationsOf(context);
        // The catch is the retail tray's identity: only SHOP_FLOOR count
        // increases squash-and-stretch with the two-beat "clack". Every
        // other vertical (and every non-add change) keeps the existing
        // softer pulse and its original haptic.
        final retailCatch =
            countChanged &&
            next.itemCount > previous.itemCount &&
            next.experiencePreset == 'SHOP_FLOOR';
        if (retailCatch) {
          if (!reduceMotion) _catch.forward(from: 0);
          AzamanHaptics.addToCart();
        } else {
          if (!reduceMotion) _pulse.forward(from: 0);
          if (countChanged && next.itemCount > previous.itemCount) {
            AzamanHaptics.toggle();
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _catch.dispose();
    super.dispose();
  }

  IconData _trayIcon(String? experiencePreset) {
    switch (experiencePreset) {
      case 'DINING_JOURNEY':
        return Icons.restaurant_rounded;
      case 'SHOP_FLOOR':
        return Icons.shopping_bag_rounded;
      default:
        return Icons.shopping_bag_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    final visible = !cart.isEmpty;

    if (visible && !_hasPresented) {
      _hasPresented = true;
    }
    if (!visible && !_hasPresented) {
      return const SizedBox.shrink();
    }

    // Oldest first: the fan paints in order, so the newest item ends up on
    // top at the right, exactly like a hand of cards.
    final fanItems = cart.items.length <= 3
        ? cart.items
        : cart.items.sublist(cart.items.length - 3);
    final fallbackIcon = _trayIcon(cart.experiencePreset);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.18),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ScaleTransition(
                scale: _catchScale,
                alignment: Alignment.bottomCenter,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      AzamanHaptics.nav();
                      widget.onTap();
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(9, 9, 14, 9),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: colors.accent.withValues(alpha: 0.34),
                            blurRadius: 20,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          _FanPreview(
                            items: fanItems,
                            fallbackIcon: fallbackIcon,
                          ),
                          const SizedBox(width: 10),
                          Container(
                            constraints: const BoxConstraints(minWidth: 34),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: AnimatedSwitcher(
                              duration: MotionTokens.accessibleDuration(
                                context,
                                const Duration(milliseconds: 180),
                              ),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: animation,
                                      child: child,
                                    ),
                                  ),
                              child: Text(
                                '${cart.itemCount}',
                                key: ValueKey(cart.itemCount),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.96),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (cart.businessName != null)
                                  Text(
                                    cart.businessName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          ScaleTransition(
                            scale: Tween<double>(begin: 1, end: 1.06)
                                .chain(CurveTween(curve: Curves.easeOutBack))
                                .animate(_pulse),
                            child: AnimatedSwitcher(
                              duration: MotionTokens.accessibleDuration(
                                context,
                                const Duration(milliseconds: 220),
                              ),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.15),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: Text(
                                '\$${cart.subtotal.toStringAsFixed(2)}',
                                key: ValueKey(cart.subtotal),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            HugeIconsSolid.arrowRight01,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Up to three bag thumbnails fanned like cards in a hand — oldest on the
/// left, newest on top at the right. The newest item is what the user just
/// committed, so it is the one that reads first.
class _FanPreview extends StatelessWidget {
  final List<CartItem> items;
  final IconData fallbackIcon;

  const _FanPreview({required this.items, required this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 42,
          height: 42,
          child: ColoredBox(
            color: Colors.white.withValues(alpha: 0.12),
            child: Icon(fallbackIcon, color: Colors.white, size: 20),
          ),
        ),
      );
    }
    return SizedBox(
      width: 66,
      height: 42,
      // Rotated cards overhang their slot by a few px; the bar's own padding
      // absorbs that, so let them paint instead of clipping the corners.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned(
              left: i * 11.0,
              child: Transform.rotate(
                angle: (i - (items.length - 1) / 2) * 0.16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child:
                        items[i].image_url == null ||
                            items[i].image_url!.isEmpty
                        ? ColoredBox(
                            color: Colors.white.withValues(alpha: 0.12),
                            child: Icon(
                              fallbackIcon,
                              color: Colors.white,
                              size: 18,
                            ),
                          )
                        : AzamanNetworkImage(
                            imageUrl: items[i].image_url!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

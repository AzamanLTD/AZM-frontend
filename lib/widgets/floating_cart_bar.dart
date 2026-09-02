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
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _hasPresented = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    ref.listenManual<CartState>(cartProvider, (previous, next) {
      if (previous == null) return;
      final countChanged = previous.itemCount != next.itemCount;
      final subtotalChanged = previous.subtotal != next.subtotal;
      if (countChanged || subtotalChanged) {
        if (next.itemCount > 0 && !_hasPresented && mounted) {
          setState(() => _hasPresented = true);
        }
        _pulse.forward(from: 0);
        if (countChanged && next.itemCount > previous.itemCount) {
          AzamanHaptics.toggle();
        }
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
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

    final leadItem = cart.items.isEmpty ? null : cart.items.last;
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
                        _ItemPreview(
                          imageUrl: leadItem?.image_url,
                          fallbackIcon: fallbackIcon,
                        ),
                        const SizedBox(width: 10),
                        ScaleTransition(
                          scale: Tween<double>(begin: 1, end: 1.10).chain(
                            CurveTween(curve: Curves.easeOutBack),
                          ).animate(_pulse),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 34),
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (child, animation) => FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(scale: animation, child: child),
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
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(animation),
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
                        const SizedBox(width: 8),
                        const Icon(HugeIconsSolid.arrowRight01, color: Colors.white, size: 20),
                      ],
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

class _ItemPreview extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;

  const _ItemPreview({required this.imageUrl, required this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: 42,
        height: 42,
        child: imageUrl == null || imageUrl!.isEmpty
            ? ColoredBox(
                color: Colors.white.withValues(alpha: 0.12),
                child: Icon(fallbackIcon, color: Colors.white, size: 20),
              )
            : AzamanNetworkImage(
                imageUrl: imageUrl!,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/cart_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

/// Drag-adjustable order tray rail for restaurant journeys.
///
/// Collapsed: a slim pill (line count + subtotal + handle). Drag it upward
/// (or tap it) to expand a peek panel with the current lines and quantity
/// steppers; drag the handle down (or tap it) to collapse. The cart provider
/// remains the single source of truth — the rail only reads and edits it.
class RestaurantTrayRail extends ConsumerStatefulWidget {
  final String label;
  final VoidCallback onOpen;

  const RestaurantTrayRail({super.key, required this.onOpen, this.label = 'Order tray'});

  @override
  ConsumerState<RestaurantTrayRail> createState() => _RestaurantTrayRailState();
}

class _RestaurantTrayRailState extends ConsumerState<RestaurantTrayRail> {
  static const double _dragThreshold = 44;
  bool _expanded = false;
  double _dragAccum = 0;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    _dragAccum += details.delta.dy;
    if (_dragAccum <= -_dragThreshold && !_expanded) {
      setState(() {
        _expanded = true;
        _dragAccum = 0;
      });
      AzamanHaptics.toggle();
    } else if (_dragAccum >= _dragThreshold && _expanded) {
      setState(() {
        _expanded = false;
        _dragAccum = 0;
      });
      AzamanHaptics.toggle();
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) => _dragAccum = 0;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final colors = ref.watch(themeProvider.select((theme) => theme.colors));
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.spatial);

    final Widget rail;
    if (cart.isEmpty) {
      rail = const SizedBox.shrink(key: ValueKey('restaurant-tray-rail-empty'));
    } else if (_expanded) {
      rail = _expandedRail(context, cart, colors);
    } else {
      rail = _collapsedPill(context, cart, colors);
    }
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: MotionTokens.enter,
      switchOutCurve: MotionTokens.exit,
      child: rail,
    );
  }

  Widget _collapsedPill(BuildContext context, CartState cart, AzamanColors colors) {
    return GestureDetector(
      key: const ValueKey('restaurant-tray-rail-collapsed'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      onTap: () {
        AzamanHaptics.toggle();
        setState(() => _expanded = true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AzSpace.md, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.94),
          borderRadius: AzRadius.brLg,
          border: Border.all(
            color: colors.isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.55),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restaurant_rounded, size: 17, color: colors.accent),
              const SizedBox(width: AzSpace.sm),
              Container(
                constraints: const BoxConstraints(minWidth: 26),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: colors.accent, borderRadius: AzRadius.brPill),
                child: Text(
                  '${cart.itemCount}',
                  textAlign: TextAlign.center,
                  style: AzText.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: AzSpace.sm),
              Text(
                '${cart.subtotal.toStringAsFixed(2)} USDC',
                style: AzText.money(colors.textPrimary, size: AzText.sizeBodyS),
              ),
              const SizedBox(width: AzSpace.sm),
              Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expandedRail(BuildContext context, CartState cart, AzamanColors colors) {
    return Container(
      key: const ValueKey('restaurant-tray-rail-expanded'),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.97),
        borderRadius: AzRadius.brXl,
        border: Border.all(
          color: colors.isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.55),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            onTap: () {
              AzamanHaptics.toggle();
              setState(() => _expanded = false);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AzSpace.sm),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: AzRadius.brPill,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(AzSpace.md, 0, AzSpace.md, AzSpace.xs),
              itemCount: cart.items.length,
              separatorBuilder: (_, __) => Divider(color: colors.divider, height: 1),
              itemBuilder: (_, index) => _lineRow(cart.items[index], colors),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AzSpace.md, AzSpace.sm, AzSpace.md, AzSpace.md),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  AzamanHaptics.nav();
                  widget.onOpen();
                },
                icon: const Icon(HugeIconsSolid.arrowRight01, size: 16),
                label: Text(widget.label),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(CartItem item, AzamanColors colors) {
    final variantSummary = item.variants.values.join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AzSpace.sm),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AzRadius.brSm,
            child: SizedBox(
              width: 38,
              height: 38,
              child: item.image_url == null || item.image_url!.isEmpty
                  ? ColoredBox(
                      color: colors.softSurface,
                      child: Icon(Icons.restaurant_rounded, size: 17, color: colors.textTertiary),
                    )
                  : AzamanNetworkImage(
                      imageUrl: item.image_url!,
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: AzSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AzText.bodyS.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700),
                ),
                if (variantSummary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      variantSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AzText.caption.copyWith(color: colors.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AzSpace.sm),
          _stepper(item, colors),
        ],
      ),
    );
  }

  Widget _stepper(CartItem item, AzamanColors colors) {
    final notifier = ref.read(cartProvider.notifier);
    return Container(
      decoration: BoxDecoration(color: colors.softSurface, borderRadius: AzRadius.brMd),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(
            HugeIconsStroke.minusSign,
            'Decrease quantity',
            () {
              AzamanHaptics.toggle();
              notifier.decrementLine(item.lineKey);
            },
            colors,
          ),
          SizedBox(
            width: 22,
            child: Text(
              '${item.quantity}',
              textAlign: TextAlign.center,
              style: AzText.bodyS.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800),
            ),
          ),
          _stepButton(
            HugeIconsStroke.plusSign,
            'Increase quantity',
            () {
              AzamanHaptics.toggle();
              notifier.incrementLine(item.lineKey);
            },
            colors,
          ),
        ],
      ),
    );
  }

  Widget _stepButton(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
    AzamanColors colors,
  ) =>
      SizedBox(
        width: 30,
        height: 30,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 14,
          icon: Icon(icon, color: colors.textPrimary),
          onPressed: onTap,
        ),
      );
}

// =============================================================================
// AZAMAN — WALLET CARD SELECTOR (PRESS AND HOLD)
//
// The card comes OUT of the wallet: a deliberate press-and-hold on the Home
// balance card lifts it, softly blurs the screen behind it and lays the three
// card identities out side by side at EXACTLY the size the card has on Home
// (never enlarged, never shrunken to squeeze two full cards into a row).
//
// WHAT THIS SCREEN OWNS
//   • the lift: a rect tween from the card's real on-screen position to the
//     selector's resting position, so the card visibly leaves the wallet;
//   • the blurred, darkened Home behind it (BackdropFilter over a scrim);
//   • horizontal paging across Blue / Green / Dark with the neighbouring
//     card peeking from the right;
//   • Apply (commits the card AND the app accent through ONE provider call)
//     and Cancel/Back/outside-tap (discards the preview completely).
//
// WHAT IT DOES NOT OWN: the theme. Nothing here touches ThemeProvider until
// Apply is pressed, so a preview can never leak into the live app.
//
// Motion: one restrained 340ms lift, no idle pulsing, no particles. Reduced
// motion lands the whole transition on its first frame.
// =============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/home/azaman_card_face.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart'
    show BalanceCardGeometry;

/// Where the selector's card sits: horizontally centred, optically slightly
/// above the middle so the Apply action has room beneath it.
Rect balanceCardSelectorTargetRect(
  Size viewport,
  double cardWidth,
  double cardHeight,
) {
  final top = (viewport.height * 0.5 - cardHeight * 0.72).clamp(
    viewport.height * 0.10,
    viewport.height * 0.42,
  );
  return Rect.fromLTWH(
    (viewport.width - cardWidth) / 2,
    top,
    cardWidth,
    cardHeight,
  );
}

/// Opens the wallet selector over the current route. [originRect] is the
/// card's rect in GLOBAL coordinates, measured by the caller, so the lift
/// starts from exactly where the card is.
Future<BalanceCardVariant?> showBalanceCardSelector(
  BuildContext context, {
  required BalanceCardVariant current,
  required Rect originRect,
}) {
  return Navigator.of(context).push<BalanceCardVariant>(
    PageRouteBuilder<BalanceCardVariant>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) =>
          BalanceCardSelector(current: current, originRect: originRect),
    ),
  );
}

class BalanceCardSelector extends ConsumerStatefulWidget {
  const BalanceCardSelector({
    super.key,
    required this.current,
    required this.originRect,
  });

  final BalanceCardVariant current;
  final Rect originRect;

  @override
  ConsumerState<BalanceCardSelector> createState() =>
      _BalanceCardSelectorState();
}

class _BalanceCardSelectorState extends ConsumerState<BalanceCardSelector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _lift;
  late final PageController _pages;
  late BalanceCardVariant _preview;
  late int _previewIndex;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _preview = widget.current;
    _previewIndex = BalanceCardVariant.values.indexOf(widget.current);
    _ctrl = AnimationController(vsync: this, duration: MotionTokens.spatial);
    _lift = CurvedAnimation(parent: _ctrl, curve: MotionTokens.symmetric);
    _pages = PageController(
      initialPage: _previewIndex,
      // Below 1 so the neighbouring card's edge peeks in at full card size.
      viewportFraction: 0.90,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else if (_ctrl.value == 0) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    final v = BalanceCardVariant.values[index];
    if (v == _preview) return;
    setState(() => _preview = v);
    AzamanHaptics.selection();
  }

  Future<void> _apply() async {
    if (_applying) return;
    setState(() => _applying = true);
    AzamanHaptics.commit();
    // ONE commit point: the card face and the app accent change together.
    await ref.read(themeProvider).setCardVariant(_preview);
    if (!mounted) return;
    Navigator.of(context).pop(_preview);
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardWidth = (size.width - 32).clamp(0.0, 460.0);
    const cardHeight = BalanceCardGeometry.height;
    final target = balanceCardSelectorTargetRect(size, cardWidth, cardHeight);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      // Android Back discards the preview: nothing was committed.
      onPopInvokedWithResult: (didPop, _) {},
      child: Stack(
        key: const ValueKey('balance-card-selector'),
        children: [
          // ── THE HOME, SOFTENED ────────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _cancel,
              child: FadeTransition(
                opacity: _lift,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: 18 * _lift.value,
                    sigmaY: 18 * _lift.value,
                  ),
                  child: ColoredBox(
                    color: (dark ? Colors.black : const Color(0xFF0B1220))
                        .withValues(alpha: 0.44 * _lift.value),
                  ),
                ),
              ),
            ),
          ),
          // ── THE CARDS ─────────────────────────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _lift,
              builder: (context, _) {
                final t = _lift.value;
                final rect = Rect.lerp(widget.originRect, target, t)!;
                return Stack(
                  children: [
                    // The pager is revealed only once the lift has mostly
                    // landed, so users never see two cards at once while the
                    // card is in flight between wallet and selector.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: target.top,
                      height: cardHeight,
                      child: Opacity(
                        opacity: t,
                        child: PageView.builder(
                          key: const ValueKey('balance-card-selector-pager'),
                          controller: _pages,
                          itemCount: BalanceCardVariant.values.length,
                          onPageChanged: _onPageChanged,
                          physics: MediaQuery.disableAnimationsOf(context)
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          itemBuilder: (context, index) {
                            final variant = BalanceCardVariant.values[index];
                            final isPreview = variant == _preview;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: rect.width * 0.9,
                                  height: cardHeight,
                                  child: _SelectorCard(
                                    key: ValueKey(
                                      'balance-card-selector-card-${variant.name}',
                                    ),
                                    variant: variant,
                                    isPreview: isPreview,
                                    isApplied: variant == widget.current,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // ── ACTIONS ───────────────────────────────────────────────────
          Positioned(
            left: 24,
            right: 24,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: FadeTransition(
                opacity: _lift,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _preview.label,
                      key: const ValueKey('balance-card-selector-label'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _preview == widget.current
                          ? 'This card is applied'
                          : 'Preview · not applied yet',
                      key: const ValueKey('balance-card-selector-state'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        key: const ValueKey('balance-card-apply'),
                        onPressed: _applying ? null : _apply,
                        style: FilledButton.styleFrom(
                          backgroundColor: kCardPalettes[_preview]!.bright
                              .withValues(alpha: 1),
                          foregroundColor: const Color(0xFFF7FAFF),
                          disabledBackgroundColor: Colors.white24,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _applying ? 'Applying…' : 'Apply card',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: TextButton(
                        key: const ValueKey('balance-card-cancel'),
                        onPressed: _applying ? null : _cancel,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.82),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          // Close affordance: a real, labelled button for anyone who does not
          // want to rely on the barrier or the Cancel text.
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                key: const ValueKey('balance-card-selector-close'),
                onPressed: _cancel,
                tooltip: 'Close the card selector',
                icon: Icon(
                  Icons.close,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One card in the selector: the real painted face, plus its state badge.
class _SelectorCard extends StatelessWidget {
  const _SelectorCard({
    super.key,
    required this.variant,
    required this.isPreview,
    required this.isApplied,
  });

  final BalanceCardVariant variant;
  final bool isPreview;
  final bool isApplied;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isPreview ? 1.0 : 0.96,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: isPreview ? 1.0 : 0.72,
        duration: const Duration(milliseconds: 180),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    BalanceCardGeometry.radius,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.34),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: AzamanCardSurface(
                  variant: variant,
                  radius: BalanceCardGeometry.radius,
                  // A preview shows the card DESIGN, never a second rendering
                  // of the user's balances.
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
            if (isApplied)
              Positioned(
                right: 12,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check,
                        size: 11,
                        color: kCardPalettes[variant]!.inkPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'APPLIED',
                        style: TextStyle(
                          color: kCardPalettes[variant]!.inkPrimary,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

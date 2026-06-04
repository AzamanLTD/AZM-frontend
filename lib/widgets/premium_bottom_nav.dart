// =============================================================================
// PREMIUM FLOATING BOTTOM NAV — "DYNAMIC ISLAND" STYLE
// Phase 3.1 | Azaman V2
//
// Design:
//   • Pill-shaped, floating 16 px above the bottom safe-area edge.
//   • Glassmorphism shell with a golden glow border.
//   • Selected item shows a filled golden indicator pill + animated icon scale.
//   • Smooth AnimatedSwitcher fade between selected states.
//   • 4 items: Home | P2P | Trades | Profile
//   • Entirely self-contained — no Scaffold.bottomNavigationBar required.
//     Render it inside a Stack as the last child over your page content.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';

// ---------------------------------------------------------------------------
// Nav item model
// ---------------------------------------------------------------------------
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

const _kNavItems = [
  _NavItem(
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: 'Home',
  ),
  _NavItem(
    icon: Icons.chat_bubble_outline_rounded,
    activeIcon: Icons.chat_bubble_rounded,
    label: 'Chat',
  ),
  _NavItem(
    icon: Icons.swap_horiz_rounded,
    activeIcon: Icons.swap_horizontal_circle_rounded,
    label: 'P2P',
  ),
  _NavItem(
    icon: Icons.savings_outlined,
    activeIcon: Icons.savings_rounded,
    label: 'Savings',
  ),
  // Profile tab removed — the user's profile is reachable via the settings
  // drawer (top-right MENU/HQ/PRO pill → drawer header card).
];

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------
class PremiumBottomNav extends ConsumerStatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const PremiumBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  ConsumerState<PremiumBottomNav> createState() => _PremiumBottomNavState();
}

class _PremiumBottomNavState extends ConsumerState<PremiumBottomNav>
    with TickerProviderStateMixin {
  // One controller per item for the icon bounce animation
  late final List<AnimationController> _bounceControllers;
  late final List<Animation<double>> _bounceAnimations;

  @override
  void initState() {
    super.initState();

    _bounceControllers = List.generate(
      _kNavItems.length,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 280),
      ),
    );

    _bounceAnimations = _bounceControllers
        .map(
          (ctrl) => Tween<double>(begin: 1.0, end: 1.28).animate(
            CurvedAnimation(parent: ctrl, curve: Curves.elasticOut),
          ),
        )
        .toList();

    // Fire initial bounce for the default selected item
    _bounceControllers[widget.selectedIndex].forward();
  }

  @override
  void didUpdateWidget(PremiumBottomNav old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _bounceControllers[old.selectedIndex].reverse();
      _bounceControllers[widget.selectedIndex]
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    for (final c in _bounceControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _handleTap(int index) {
    if (index == widget.selectedIndex) return;
    HapticFeedback.selectionClick();
    widget.onItemSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 24,
      right: 24,
      bottom: bottomPadding + 16,
      child: _PillShell(
        colors: colors,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(
            _kNavItems.length,
            (i) => _NavButton(
              item: _kNavItems[i],
              isSelected: widget.selectedIndex == i,
              colors: colors,
              bounceAnimation: _bounceAnimations[i],
              onTap: () => _handleTap(i),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pill shell — glass + glow
// ---------------------------------------------------------------------------
class _PillShell extends StatelessWidget {
  final AzamanColors colors;
  final Widget child;
  const _PillShell({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface.withOpacity(0.90),
            colors.background.withOpacity(0.92),
          ],
        ),
        border: Border.all(
          color: colors.glow.withOpacity(0.20),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.glow.withOpacity(0.10),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual nav button
// ---------------------------------------------------------------------------
class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final AzamanColors colors;
  final Animation<double> bounceAnimation;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.colors,
    required this.bounceAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon with indicator pill
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: isSelected
                      ? colors.glow.withOpacity(0.15)
                      : Colors.transparent,
                ),
                child: ScaleTransition(
                  scale: bounceAnimation,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: child,
                    ),
                    child: Icon(
                      isSelected ? item.activeIcon : item.icon,
                      key: ValueKey(isSelected),
                      color: isSelected ? colors.glow : colors.textTertiary,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // Label
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isSelected ? colors.glow : colors.textTertiary,
                  fontSize: 9,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w400,
                  letterSpacing: isSelected ? 0.8 : 0.3,
                ),
                child: Text(item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// lib/widgets/parallax_header_delegate.dart
// =============================================================================
// PARALLAX HEADER DELEGATE — Scroll-driven hero morph
//
// Used in BusinessProfileScreen and HotelBookingScreen. The hero image
// scrolls at 0.5x speed (parallax) and the title/bar fade in as it
// collapses, producing the "Wonderous" effect.
//
// Usage in a CustomScrollView:
//   SliverPersistentHeader(
//     pinned: true,
//     delegate: ParallaxHeaderDelegate(
//       imageUrl: business.logoUrl,
//       title: business.businessName,
//       minExtent: 56 + MediaQuery.of(context).padding.top,
//       maxExtent: 280,
//       actions: [IconButton(...)],
//     ),
//   )
// =============================================================================
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ParallaxHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final double minExtent;
  final double maxExtent;
  final List<Widget> actions;
  final Color? accentColor;
  final Widget? fallbackWidget;

  ParallaxHeaderDelegate({
    required this.imageUrl,
    required this.title,
    this.subtitle,
    required this.minExtent,
    required this.maxExtent,
    this.actions = const [],
    this.accentColor,
    this.fallbackWidget,
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final expandPercent =
        1.0 - (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);

    // Parallax: image moves at 0.5x scroll speed
    final imageHeight = maxExtent;
    final imageOffset = shrinkOffset * 0.5;

    // Title opacity: fades in as header collapses
    final compactTitleOpacity = (1.0 - expandPercent).clamp(0.0, 1.0);
    final expandedTitleOpacity = expandPercent.clamp(0.0, 1.0);

    return SizedBox(
      height: maxExtent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Parallax background image
          Positioned(
            top: -imageOffset,
            left: 0, right: 0,
            height: imageHeight,
            child: ClipRect(
              child: OverflowBox(
                maxHeight: imageHeight,
                alignment: Alignment.topCenter,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _fallbackGradient(isDark),
                        errorWidget: (_, __, ___) => _fallbackGradient(isDark),
                      )
                    : fallbackWidget ?? _fallbackGradient(isDark),
              ),
            ),
          ),

          // Gradient overlay for legibility
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15 * expandPercent),
                    Colors.black.withValues(alpha: 0.05),
                    isDark ? Colors.black.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.3),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // Frosted top bar (strengthens as it collapses)
          Positioned(
            top: 0, left: 0, right: 0,
            height: minExtent,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 16 * compactTitleOpacity,
                  sigmaY: 16 * compactTitleOpacity,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.black : Colors.white)
                        .withValues(alpha: 0.4 * compactTitleOpacity),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06 * compactTitleOpacity),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Compact title (fades in as header collapses)
          Positioned(
            top: 0, left: 0, right: 0,
            height: minExtent,
            child: SafeArea(
              bottom: false,
              child: NavigationToolbar(
                leading: Navigator.of(context).canPop()
                    ? IconButton(
                        icon: Icon(Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: compactTitleOpacity > 0.5
                                ? (isDark ? Colors.white : Colors.black87)
                                : Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    : null,
                middle: Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 16, fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ).animate().fadeIn(duration: 200.ms),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
          ),

          // Expanded title block (fades out as header collapses)
          Positioned(
            left: 20, right: 20, bottom: 16,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26 * (0.6 + 0.4 * expandPercent),
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8, height: 1.1,
                      shadows: [Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)],
                    ),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ).animate().fadeIn(duration: 300.ms),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13, fontWeight: FontWeight.w500,
                      shadows: [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
                    )).animate().fadeIn(delay: 100.ms, duration: 300.ms),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackGradient(bool isDark) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: accentColor != null
              ? [accentColor!, accentColor!.withValues(alpha: 0.5)]
              : [(isDark ? const Color(0xFF1E2329) : const Color(0xFFD4AF37)),
                 (isDark ? const Color(0xFF0B0E11) : const Color(0xFFF0B90B))],
        ),
      ),
      child: Center(child: Icon(Icons.storefront_outlined, size: 64, color: Colors.white.withValues(alpha: 0.3))),
    );
  }

  @override bool shouldRebuild(ParallaxHeaderDelegate old) =>
      imageUrl != old.imageUrl || title != old.title || subtitle != old.subtitle;
}

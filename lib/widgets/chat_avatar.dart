import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ChatAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final bool isOnline;
  final bool showOnlineDot;

  const ChatAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 48,
    this.isOnline = false,
    this.showOnlineDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final gradient = _nameGradient(name);
    // Squircle curvature — matches StoryRing's proportions (2026-07-06) so
    // avatars read consistently across the status bar and chat surfaces
    // instead of stories being squircles and chat rows being plain circles.
    final radius = size * 0.34;
    final shape = ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius));

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: ShapeDecoration(
              shape: shape,
              gradient: hasImage ? null : gradient,
            ),
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: shape),
              child: hasImage
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                      placeholder: (_, __) => _initialsWidget(name, size),
                      errorWidget: (_, __, ___) => _initialsWidget(name, size),
                    )
                  : _initialsWidget(name, size),
            ),
          ),
          if (showOnlineDot)
            Positioned(
              bottom: size * 0.02,
              right: size * 0.02,
              child: _OnlineDot(size: size * 0.28, isOnline: isOnline),
            ),
        ],
      ),
    );
  }

  Widget _initialsWidget(String name, double size) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.38,
        ),
      ),
    );
  }

  LinearGradient _nameGradient(String name) {
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final hue1 = (hash % 360).toDouble();
    final hue2 = ((hash ~/ 360) % 360).toDouble();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HSLColor.fromAHSL(1.0, hue1, 0.55, 0.45).toColor(),
        HSLColor.fromAHSL(1.0, hue2, 0.50, 0.35).toColor(),
      ],
    );
  }
}

class _OnlineDot extends StatelessWidget {
  final double size;
  final bool isOnline;
  const _OnlineDot({required this.size, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? const Color(0xFF02C076) : Colors.grey;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).scaffoldBackgroundColor,
          width: 2,
        ),
      ),
    )
    .animate(onComplete: (c) => isOnline ? c.repeat() : c.stop())
    .then()
    .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.3, 1.3), duration: 1200.ms, curve: Curves.easeInOut)
    .scale(begin: const Offset(1.3, 1.3), end: const Offset(1.0, 1.0), duration: 1200.ms, curve: Curves.easeInOut);
  }
}

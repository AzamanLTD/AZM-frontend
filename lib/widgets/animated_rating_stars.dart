// lib/widgets/animated_rating_stars.dart
// =============================================================================
// ANIMATED RATING STARS — Display & interactive modes
// Display: AnimatedRatingStars(rating: 4.5, size: 16)
// Interactive: AnimatedRatingStars.interactive(initialRating: 0, onRatingChanged: (r) => ...)
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AnimatedRatingStars extends StatefulWidget {
  final double rating;
  final double size;
  final Color? filledColor;
  final Color? emptyColor;
  final bool interactive;
  final ValueChanged<double>? onRatingChanged;

  const AnimatedRatingStars({super.key, required this.rating, this.size = 16, this.filledColor, this.emptyColor, this.interactive = false, this.onRatingChanged});

  const AnimatedRatingStars.interactive({super.key, required double initialRating, this.size = 36, this.filledColor, this.emptyColor, required this.onRatingChanged})
      : rating = initialRating, interactive = true;

  @override State<AnimatedRatingStars> createState() => _AnimatedRatingStarsState();
}

class _AnimatedRatingStarsState extends State<AnimatedRatingStars> {
  late double _currentRating;
  @override void initState() { super.initState(); _currentRating = widget.rating; }

  @override Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filled = widget.filledColor ?? const Color(0xFFF0B90B);
    final empty = widget.emptyColor ?? (isDark ? Colors.white12 : Colors.black12);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starValue = i + 1.0;
        final isFilled = _currentRating >= starValue;
        final isHalf = !isFilled && _currentRating >= starValue - 0.5;
        return GestureDetector(
          onTap: widget.interactive ? () { setState(() => _currentRating = starValue); widget.onRatingChanged?.call(starValue); } : null,
          child: Padding(
            padding: EdgeInsets.only(right: i < 4 ? widget.size * 0.15 : 0),
            child: _buildStar(isFilled, isHalf, filled, empty, i),
          ),
        );
      }),
    );
  }

  Widget _buildStar(bool isFilled, bool isHalf, Color filled, Color empty, int index) {
    final icon = isFilled ? Icons.star_rounded : isHalf ? Icons.star_half_rounded : Icons.star_outline_rounded;
    final star = Icon(icon, size: widget.size, color: isFilled || isHalf ? filled : empty);
    if (widget.interactive) {
      return star.animate(target: isFilled ? 1 : 0)
        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.15, 1.15), duration: 200.ms, curve: Curves.easeOutBack)
        .then().scale(begin: const Offset(1.15, 1.15), end: const Offset(1.0, 1.0), duration: 150.ms);
    }
    return star.animate().scale(begin: const Offset(0, 0), end: const Offset(1, 1), delay: (index * 80).ms, duration: 300.ms, curve: Curves.easeOutBack);
  }
}

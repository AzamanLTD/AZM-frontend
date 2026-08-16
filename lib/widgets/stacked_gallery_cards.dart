import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/image_lightbox.dart'; // existing lightbox — reused as-is
import 'package:azaman/widgets/azaman_network_image.dart';

class StackedGalleryCards extends ConsumerStatefulWidget {
  final List<String> urls;
  final double width;
  final double height;

  const StackedGalleryCards({
    required this.urls,
    this.width = 130,
    this.height = 96,
    super.key,
  });

  @override
  ConsumerState<StackedGalleryCards> createState() => _StackedGalleryCardsState();
}

class _StackedGalleryCardsState extends ConsumerState<StackedGalleryCards> {
  late List<String> _order; // mutable stacking order, front = index 0
  double _dragDx = 0;

  // Cap how many cards physically render behind the front one
  static const int _maxVisibleStack = 4;

  @override
  void initState() {
    super.initState();
    _order = List.of(widget.urls);
  }

  @override
  void didUpdateWidget(covariant StackedGalleryCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls != widget.urls) {
      _order = List.of(widget.urls);
    }
  }

  void _bringToFront(int index) {
    setState(() {
      final item = _order.removeAt(index);
      _order.insert(0, item);
    });
  }

  void _openLightbox() {
    final initialIndex = widget.urls.indexOf(_order.first);
    ImageLightbox.show(
      context,
      urls: widget.urls,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return const SizedBox.shrink();
    final colors = ref.watch(themeProvider).colors;
    final visible = _order.take(_maxVisibleStack).toList();

    return SizedBox(
      width: widget.width + (_maxVisibleStack - 1) * 6.0,
      height: widget.height + (_maxVisibleStack - 1) * 10.0,
      child: Stack(
        children: [
          for (int i = visible.length - 1; i >= 0; i--)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top: i * 8.0,
              left: i * 5.0,
              child: GestureDetector(
                onTap: i == 0
                    ? _openLightbox
                    : () => _bringToFront(i), // tap a peeking card -> bring it forward
                onHorizontalDragUpdate: i == 0
                    ? (d) => setState(() => _dragDx += d.delta.dx)
                    : null,
                onHorizontalDragEnd: i == 0
                    ? (d) {
                        if (_dragDx.abs() > 90 && _order.length > 1) {
                          setState(() {
                            final front = _order.removeAt(0);
                            _order.add(front);
                          });
                        }
                        setState(() => _dragDx = 0);
                      }
                    : null,
                child: Transform.translate(
                  offset: Offset(i == 0 ? _dragDx : 0, 0),
                  child: Transform.rotate(
                    angle: i == 0 ? (_dragDx / 900).clamp(-0.12, 0.12) : 0,
                    child: Hero(
                      tag: 'lightbox_${_order[i]}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.divider, width: 0.6),
                          ),
                          child: AzamanNetworkImage(
                            imageUrl: _order[i],
                            width: widget.width,
                            height: widget.height,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: widget.width, height: widget.height,
                              color: colors.softSurface,
                            ),
                            errorWidget: (_, __, ___) => Container(
                              width: widget.width, height: widget.height,
                              color: colors.softSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.urls.length > _maxVisibleStack)
            Positioned(
              right: 0, top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.divider, width: 0.6),
                ),
                child: Text('+${widget.urls.length - _maxVisibleStack + 1}',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: colors.textSecondary)),
              ),
            ),
        ],
      ),
    );
  }
}

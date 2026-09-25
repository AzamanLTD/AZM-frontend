// lib/widgets/image_lightbox.dart
// =============================================================================
// IMAGE LIGHTBOX — Marketplace Premium Upgrade (2026-06-21)
//
// Full-screen swipeable photo viewer. Uses Hero animations for a smooth
// expand transition. No new packages required:
//   • PageView for swiping between images
//   • InteractiveViewer for pinch-to-zoom
//   • Hero for expand/collapse animation
//
// Usage:
//   ImageLightbox.show(context, urls: imageUrls, initialIndex: tappedIndex);
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

class ImageLightbox extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const ImageLightbox({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  /// Show the lightbox as a full-screen route.
  static Future<void> show(
    BuildContext context, {
    required List<String> urls,
    int initialIndex = 0,
  }) {
    if (urls.isEmpty) return Future.value();
    return Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: ImageLightbox(urls: urls, initialIndex: initialIndex),
        ),
      ),
    );
  }

  @override
  State<ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<ImageLightbox> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_current + 1} / ${widget.urls.length}',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              return InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(
                  child: Hero(
                    tag: 'lightbox_${widget.urls[i]}',
                    child: AzamanNetworkImage(
                      imageUrl: widget.urls[i],
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(color: Colors.white54),
                      ),
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.white54, size: 48),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Dot indicators
          if (widget.urls.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.urls.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _current ? 20 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _current
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

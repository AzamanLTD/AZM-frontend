// lib/screens/marketplace/business_stories_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class BusinessStoriesScreen extends ConsumerStatefulWidget {
  final String bizId;
  final String businessName;
  final String? logoUrl;
  final List<String> storyUrls;

  const BusinessStoriesScreen({
    super.key,
    required this.bizId,
    required this.businessName,
    this.logoUrl,
    required this.storyUrls,
  });

  @override
  ConsumerState<BusinessStoriesScreen> createState() =>
      _BusinessStoriesScreenState();
}

class _BusinessStoriesScreenState extends ConsumerState<BusinessStoriesScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  bool _isPaused = false;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && !_isPaused) _goNext();
          });
    _progressController.forward();
  }

  void _goNext() {
    AzamanHaptics.nav();
    if (_currentIndex < widget.storyUrls.length - 1) {
      setState(() => _currentIndex++);
      _progressController.reset();
      _progressController.forward();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goPrevious() {
    AzamanHaptics.nav();
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _progressController.reset();
      _progressController.forward();
    }
  }

  void _pause() {
    setState(() => _isPaused = true);
    _progressController.stop();
  }

  void _resume() {
    setState(() => _isPaused = false);
    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragUpdate: (d) {
          if (d.delta.dy > 8) Navigator.of(context).pop();
        },
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: widget.storyUrls[_currentIndex],
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.4)
                  ],
                  stops: const [0.0, 0.15, 0.85, 1.0],
                ),
              ),
            ),
            // Progress bars
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(
                  widget.storyUrls.length,
                  (i) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, _) {
                          final progress = i < _currentIndex
                              ? 1.0
                              : i > _currentIndex
                                  ? 0.0
                                  : _progressController.value;
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation(
                                  Colors.white),
                              minHeight: 2.5,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Business header
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  if (widget.logoUrl != null)
                    CircleAvatar(
                      backgroundImage:
                          CachedNetworkImageProvider(widget.logoUrl!),
                      radius: 16,
                    )
                  else
                    CircleAvatar(
                      backgroundColor: colors.accent,
                      radius: 16,
                      child: Icon(
                        Icons.storefront_outlined,
                        size: 16,
                        color: colors.background,
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.businessName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Tap zones
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: _goPrevious,
                    behavior: HitTestBehavior.translucent,
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: GestureDetector(
                    onTap: _goNext,
                    behavior: HitTestBehavior.translucent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

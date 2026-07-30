// =============================================================================
// MEDIA VIEWER SCREEN — Phase 11.1
//
// Full-screen pinch-zoom gallery for chat media (WhatsApp/Telegram parity).
// Supports: images with InteractiveViewer, videos with VideoPlayer,
// swipe between items via PageView, Hero transitions, save/share/forward.
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:azaman/config.dart';
import 'package:azaman/widgets/chat_media_bubble.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<MediaViewerItem> items;
  final int initialIndex;
  final String heroTag;

  const MediaViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    required this.heroTag,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

/// A single media item for the viewer.
class MediaViewerItem {
  final String url;
  final String type; // IMAGE | VIDEO
  final String? caption;

  const MediaViewerItem({
    required this.url,
    required this.type,
    this.caption,
  });
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showUI = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${AppConfig.baseUrl}$url';
  }

  void _toggleUI() {
    setState(() => _showUI = !_showUI);
  }

  Future<void> _saveMedia() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    HapticFeedback.lightImpact();
    try {
      final item = widget.items[_currentIndex];
      final url = _resolveUrl(item.url);
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('Download failed');

      final ext = item.type == 'VIDEO' ? 'mp4' : 'png';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/azaman_media_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(res.bodyBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${file.path}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareMedia() async {
    HapticFeedback.lightImpact();
    try {
      final item = widget.items[_currentIndex];
      final url = _resolveUrl(item.url);
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('Download failed');

      final ext = item.type == 'VIDEO' ? 'mp4' : 'png';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/azaman_share_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(res.bodyBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: item.caption,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── PageView for swiping between media items ──────────────────────
          GestureDetector(
            onTap: _toggleUI,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (context, i) {
                final item = widget.items[i];
                final isCurrent = i == _currentIndex;
                if (item.type == 'VIDEO') {
                  return _VideoViewer(
                    url: _resolveUrl(item.url),
                    heroTag: isCurrent ? widget.heroTag : null,
                  );
                }
                return _ImageViewer(
                  url: _resolveUrl(item.url),
                  heroTag: isCurrent ? '${widget.heroTag}_$i' : null,
                );
              },
            ),
          ),

          // ── Top bar (close, counter, save, share) ─────────────────────────
          if (_showUI) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                  ),
                ),
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  right: 8,
                  bottom: 12,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 26),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    if (widget.items.length > 1) ...[
                      const Spacer(),
                      Text(
                        '${_currentIndex + 1} / ${widget.items.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download_rounded, color: Colors.white, size: 24),
                      onPressed: _saveMedia,
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: Colors.white, size: 24),
                      onPressed: _shareMedia,
                    ),
                  ],
                ),
              ),
            ),

            // ── Caption at bottom ──────────────────────────────────────────
            if (widget.items[_currentIndex].caption != null &&
                widget.items[_currentIndex].caption!.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                    ),
                  ),
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                    top: 24,
                  ),
                  child: Text(
                    widget.items[_currentIndex].caption!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE VIEWER — pinch-zoom with InteractiveViewer + Hero transition
// ─────────────────────────────────────────────────────────────────────────────
class _ImageViewer extends StatelessWidget {
  final String url;
  final String? heroTag;

  const _ImageViewer({required this.url, this.heroTag});

  @override
  Widget build(BuildContext context) {
    Widget image = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
      ),
    );

    // Wrap in InteractiveViewer for pinch-zoom
    image = InteractiveViewer(
      minScale: 0.8,
      maxScale: 5.0,
      panEnabled: true,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      child: image,
    );

    // Hero transition for smooth enter/exit
    if (heroTag != null) {
      return Hero(tag: heroTag!, child: image);
    }
    return image;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIDEO VIEWER — VideoPlayer with controls
// ─────────────────────────────────────────────────────────────────────────────
class _VideoViewer extends StatefulWidget {
  final String url;
  final String? heroTag;

  const _VideoViewer({required this.url, this.heroTag});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller!.initialize().then((_) {
      if (mounted) {
        setState(() => _isInitialized = true);
        _controller!.play();
        _controller!.setLooping(true);
        _isPlaying = true;
        _controller!.addListener(_listener);
      }
    }).catchError((e) {
      if (mounted) {
        setState(() => _isInitialized = false);
      }
    });
  }

  void _listener() {
    if (mounted && _controller != null) {
      final playing = _controller!.value.isPlaying;
      if (playing != _isPlaying) {
        setState(() => _isPlaying = playing);
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_listener);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
      );
    }

    final aspectRatio = _controller!.value.aspectRatio;

    Widget content = Stack(
      alignment: Alignment.center,
      children: [
        // Video
        Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),

        // Tap to play/pause
        if (_showControls)
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),

        // Progress bar at bottom
        if (_showControls)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
              padding: const EdgeInsets.only(top: 24, left: 8, right: 8, bottom: 8),
            ),
          ),
      ],
    );

    if (widget.heroTag != null) {
      content = Hero(tag: widget.heroTag!, child: content);
    }
    return content;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/story_model.dart';
import '../providers/story_provider.dart';
import '../widgets/story_ring.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:video_player/video_player.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
// Note: VendorPage and StoryVideoPlayer imports may be needed depending on project structure

class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;
  const StoryViewerScreen({super.key, required this.groups, this.initialGroupIndex = 0});

  /// 2026-07-08: container-transform-style open (fade + scale-up-from-ring)
  /// instead of a flat MaterialPageRoute push. Popping — whether via the
  /// back gesture, the back button, or the viewer auto-advancing past the
  /// last story and calling Navigator.pop itself — automatically reverses
  /// this exact transition, since Flutter routes always play their own
  /// transitionsBuilder backwards on pop. No extra "closing" code needed.
  static Future<void> open(
    BuildContext context, {
    required List<StoryGroup> groups,
    int initialGroupIndex = 0,
  }) {
    return Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      opaque: true,
      pageBuilder: (_, __, ___) =>
          StoryViewerScreen(groups: groups, initialGroupIndex: initialGroupIndex),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ));
  }

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}
 
class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _groupIndex;
  int _storyIndex = 0;
  late AnimationController _progress;
  bool _isPaused = false;
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  final _replyController = TextEditingController();
  bool _replySending = false;
 
  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _progress = AnimationController(vsync: this)
      ..addStatusListener((status) { if (status == AnimationStatus.completed) _advance(); });
    _playCurrent();
  }
 
  StoryGroup get _group => widget.groups[_groupIndex];
  StoryItem get _story => _group.stories[_storyIndex];
 
  void _playCurrent() {
    _videoController?.dispose();
    _videoController = null;
    _videoReady = false;

    if (_story.mediaType == 'VIDEO') {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(_story.mediaUrl))
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _videoReady = true);
            _videoController!.play();
            _videoController!.setLooping(false);
            // Use video duration if available, fallback to config
            final dur = _videoController!.value.duration.inSeconds;
            _progress
              ..duration = Duration(seconds: dur > 0 ? dur : _story.durationSeconds)
              ..forward(from: 0);
            _videoController!.setVolume(0.0); // muted by default in stories
          }
        });
      // Start progress even before video loads (fallback)
      _progress
        ..duration = Duration(seconds: _story.durationSeconds)
        ..forward(from: 0);
    } else {
      _progress
        ..duration = Duration(seconds: _story.durationSeconds)
        ..forward(from: 0);
    }
    ref.read(storyFeedProvider.notifier).markViewed(_story.id);
  }
 
  void _advance() {
    if (_storyIndex < _group.stories.length - 1) {
      setState(() => _storyIndex++);
      _playCurrent();
    } else if (_groupIndex < widget.groups.length - 1) {
      setState(() { _groupIndex++; _storyIndex = 0; });
      _playCurrent();
    } else {
      Navigator.of(context).pop();
    }
  }
 
  void _rewind() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _playCurrent();
    } else if (_groupIndex > 0) {
      setState(() { _groupIndex--; _storyIndex = widget.groups[_groupIndex].stories.length - 1; });
      _playCurrent();
    }
  }
 
  @override
  void dispose() {
    _videoController?.dispose();
    _replyController.dispose();
    _progress.dispose();
    super.dispose();
  }
 
  Future<void> _sendReply() async {
    final msg = _replyController.text.trim();
    if (msg.isEmpty || _replySending) return;
    setState(() => _replySending = true);
    HapticFeedback.lightImpact();
    final ok = await ref.read(storyFeedProvider.notifier).replyStory(_story.id, msg);
    if (mounted) {
      _replyController.clear();
      setState(() => _replySending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Reply sent!' : 'Failed to send reply'),
          duration: const Duration(seconds: 1),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          final w = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < w * 0.35) { _progress.stop(); _rewind(); }
          else { _progress.stop(); _advance(); }
        },
        onLongPressStart: (_) { _progress.stop(); setState(() => _isPaused = true); },
        onLongPressEnd: (_) { _progress.forward(); setState(() => _isPaused = false); },
        child: Stack(fit: StackFit.expand, children: [
          _story.mediaType == 'VIDEO'
            ? (_videoReady && _videoController != null
                ? Center(child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ))
                : const Center(child: CircularProgressIndicator(color: Colors.white70)))
            : AzamanNetworkImage(
                imageUrl: _story.mediaUrl, fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.black),
                errorWidget: (_, __, ___) => Container(color: Colors.black12, child: const Center(child: Icon(Icons.broken_image, color: Colors.white30, size: 48))),
              ),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
            stops: [0.0, 0.2, 0.7, 1.0]))),
          if (_isPaused)
            Center(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.pause, color: Colors.white, size: 36))).animate().fadeIn(duration: 150.ms),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(
                    children: List.generate(
                      _group.stories.length, 
                      (i) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: AnimatedBuilder(
                              animation: _progress, 
                              builder: (_, __) => LinearProgressIndicator(
                                value: i < _storyIndex ? 1 : (i == _storyIndex ? _progress.value : 0),
                                backgroundColor: Colors.white.withValues(alpha: 0.2),
                                valueColor: AlwaysStoppedAnimation(_story.boosted ? Colors.amberAccent : Colors.white),
                                minHeight: 3
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      StoryRing(avatarUrl: _group.authorAvatarUrl, hasUnseenStory: false, isBoosted: false, size: 36),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_group.authorUsername, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('${_storyIndex + 1} of ${_group.stories.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w500)),
                      ]),
                      if (_story.boosted) ...[
                        const SizedBox(width: 8),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.amberAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.bolt, color: Colors.amberAccent, size: 12), SizedBox(width: 2),
                            Text('BOOSTED', style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.w800)),
                          ])),
                      ],
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 22), onPressed: () => Navigator.of(context).pop()),
                    ]
                  )
                ),
              ]
            )
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(
              top: false, 
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    if (_story.linkedBizId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () { /* Navigator.of(context).push(MaterialPageRoute(builder: (_) => VendorPage(bizId: _story.linkedBizId!))); */ },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                            alignment: Alignment.center,
                            child: const Text('Visit Store', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black))
                          )
                        )
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1), 
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5)
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.camera_alt_outlined, color: Colors.white.withValues(alpha: 0.6), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _replyController,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: 'Reply to story...',
                                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                                      border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12)
                                    ),
                                    onSubmitted: (msg) => _sendReply(),
                                  )
                                ),
                                Icon(Icons.emoji_emotions_outlined, color: Colors.white.withValues(alpha: 0.6), size: 20),
                              ]
                            )
                          )
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _sendReply,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                              color: _replyController.text.isNotEmpty
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5)
                            ),
                            alignment: Alignment.center,
                            child: _replySending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : Icon(Icons.send,
                                  color: _replyController.text.isNotEmpty
                                    ? Colors.black
                                    : Colors.white.withValues(alpha: 0.7),
                                  size: 18),
                          )
                        ),
                      ]
                    ),
                  ]
                )
              )
            )
          ),
        ]),
      ),
    );
  }
}

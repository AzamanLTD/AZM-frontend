import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/story_model.dart';
import '../providers/story_provider.dart';
import '../widgets/story_ring.dart';
// Note: VendorPage and StoryVideoPlayer imports may be needed depending on project structure

class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;
  const StoryViewerScreen({super.key, required this.groups, this.initialGroupIndex = 0});
 
  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}
 
class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _groupIndex;
  int _storyIndex = 0;
  late AnimationController _progress;
 
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
    _progress
      ..duration = Duration(seconds: _story.durationSeconds)
      ..forward(from: 0);
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
  void dispose() { _progress.dispose(); super.dispose(); }
 
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
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        child: Stack(fit: StackFit.expand, children: [
          _story.mediaType == 'VIDEO'
            ? const Center(child: Text('Video player placeholder', style: TextStyle(color: Colors.white))) // placeholder
            : Image.network(_story.mediaUrl, fit: BoxFit.cover),
 
          // gradient scrim for legibility of top/bottom overlays
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black45, Colors.transparent, Colors.black54],
            stops: [0.0, 0.3, 1.0],
          ))),
 
          SafeArea(child: Column(children: [
            // progress bars, one per story in this group
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(children: List.generate(_group.stories.length, (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (_, __) => LinearProgressIndicator(
                      value: i < _storyIndex ? 1 : (i == _storyIndex ? _progress.value : 0),
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                      minHeight: 2.5,
                    ),
                  ),
                ),
              ))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                StoryRing(avatarUrl: _group.authorAvatarUrl, hasUnseenStory: false, isBoosted: false, size: 34),
                const SizedBox(width: 10),
                Text(_group.authorUsername, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                if (_story.boosted) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.bolt, color: Colors.amberAccent, size: 16),
                ],
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
          ])),
 
          if (_story.linkedBizId != null)
            Positioned(
              left: 20, right: 20, bottom: 28,
              child: GestureDetector(
                onTap: () {
                    // Navigator.of(context).push(MaterialPageRoute(builder: (_) => VendorPage(bizId: _story.linkedBizId!)));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                  alignment: Alignment.center,
                  child: const Text('Visit Store', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// Compatibility shim: the story viewer moved to
// lib/widgets/stories/viewer/ (Overhaul 05). The public `StoryViewerScreen`
// class and its `open()` signature are unchanged, so the existing callers
// (friends hub, messages hub, marketplace home) keep importing this path
// without edits.
export '../widgets/stories/viewer/story_viewer_screen.dart';

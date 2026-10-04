// Media controller: one story's media load (Overhaul 05 §3.2).
// Review pass 2: the dispose-during-prepare race — a video initialize()
// completing after the viewer (and its page) is gone must not touch the
// disposed ChangeNotifier.
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/story_model.dart';
import 'package:azaman/widgets/stories/viewer/story_media_controller.dart';

StoryItem _videoItem() => StoryItem(
      id: 'v0',
      mediaUrl: 'https://cdn.example.com/v0.mp4',
      mediaType: 'IMAGE', // feed sends nothing; the sniffer decides
      durationSeconds: 5,
      boosted: false,
      seen: false,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  test('dispose racing prepare() completes without touching the disposed notifier',
      () async {
    final controller = StoryMediaController(_videoItem());
    final prepare = controller.prepare();
    // Viewer dismissed while initialize() is still in flight.
    controller.dispose();
    await prepare; // must not throw "used after being disposed"
  });

  test('image kind sniffing treats extension-less signed URLs as images',
      () {
    expect(
        StoryMediaKindSniffer.sniff('https://cdn.example.com/abc?sig=xyz'),
        StoryMediaKind.image);
    expect(
        StoryMediaKindSniffer.sniff('https://cdn.example.com/clip.mp4?sig=1'),
        StoryMediaKind.video);
  });
}

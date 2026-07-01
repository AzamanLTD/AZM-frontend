import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/story_model.dart';

final storyFeedProvider = StateNotifierProvider.autoDispose<StoryFeedNotifier, AsyncValue<List<StoryGroup>>>(
  (ref) => StoryFeedNotifier()..load(),
);
 
class StoryFeedNotifier extends StateNotifier<AsyncValue<List<StoryGroup>>> {
  StoryFeedNotifier() : super(const AsyncValue.loading());
 
  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await apiClient.get('/stories/feed');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final groups = (body['groups'] as List? ?? [])
        .map((g) => StoryGroup.fromJson(g as Map<String, dynamic>)).toList();
      state = AsyncValue.data(groups);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
 
  Future<void> markViewed(String storyId) async {
    try { await apiClient.post('/stories/$storyId/view', {}); } catch (_) {}
    // Optimistically flip local seen-state so the ring updates immediately.
    state.whenData((groups) {
      state = AsyncValue.data(groups.map((g) => StoryGroup(
        authorId: g.authorId, authorUsername: g.authorUsername, authorAvatarUrl: g.authorAvatarUrl,
        isBoosted: g.isBoosted,
        hasUnseen: g.stories.any((s) => s.id != storyId && !s.seen),
        stories: g.stories.map((s) => s.id == storyId
          ? StoryItem(id: s.id, mediaUrl: s.mediaUrl, mediaType: s.mediaType, caption: s.caption,
              linkedBizId: s.linkedBizId, durationSeconds: s.durationSeconds, boosted: s.boosted,
              seen: true, createdAt: s.createdAt)
          : s).toList(),
      )).toList());
    });
  }
 
  Future<void> boost(String storyId, int amount) async {
    await apiClient.post('/stories/$storyId/boost', {'amount': amount});
    await load();
  }
}

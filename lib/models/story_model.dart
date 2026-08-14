class StoryItem {
  final String id;
  final String mediaUrl;
  final String mediaType; // IMAGE | VIDEO
  final String? caption;
  final String? linkedBizId;
  final int durationSeconds;
  final bool boosted;
  final bool seen;
  final DateTime createdAt;
 
  const StoryItem({
    required this.id, required this.mediaUrl, required this.mediaType,
    this.caption, this.linkedBizId, required this.durationSeconds,
    required this.boosted, required this.seen, required this.createdAt,
  });
 
  factory StoryItem.fromJson(Map<String, dynamic> j) => StoryItem(
    id: j['id'].toString(),
    mediaUrl: j['mediaUrl'].toString(),
    mediaType: j['mediaType']?.toString() ?? 'IMAGE',
    caption: j['caption']?.toString(),
    linkedBizId: j['linkedBizId']?.toString(),
    durationSeconds: (j['durationSeconds'] as num?)?.toInt() ?? 5,
    boosted: j['boosted'] == true,
    seen: j['seen'] == true,
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
  );
}
 
class StoryGroup {
  final int authorId;
  final String authorUsername;
  final String? authorAvatarUrl;
  final bool hasUnseen;
  final bool isBoosted;
  final List<StoryItem> stories;
 
  const StoryGroup({
    required this.authorId, required this.authorUsername, this.authorAvatarUrl,
    required this.hasUnseen, required this.isBoosted, required this.stories,
  });
 
  factory StoryGroup.fromJson(Map<String, dynamic> j) {
    final author = j['author'] as Map<String, dynamic>? ?? {};
    return StoryGroup(
      authorId: (j['authorId'] as num?)?.toInt() ?? 0,
      authorUsername: author['username']?.toString() ?? '',
      authorAvatarUrl: author['profilePictureUrl']?.toString(),
      hasUnseen: j['hasUnseen'] == true,
      isBoosted: j['isBoosted'] == true,
      stories: (j['stories'] as List? ?? [])
        .map((s) => StoryItem.fromJson(s as Map<String, dynamic>)).toList(),
    );
  }
}

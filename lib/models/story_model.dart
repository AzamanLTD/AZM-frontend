import 'package:azaman/models/marketplace_booking_models.dart'
    show BusinessStory;

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

  /// Whether the FEED actually supplied [durationSeconds].
  ///
  /// GET /api/stories/feed returns only
  /// {id, mediaUrl, caption, linkedBizId, boosted, seen, createdAt} today, so
  /// [durationSeconds] is the 5-second image fallback unless this is non-null.
  /// The viewer must not present a server-supplied duration that the server
  /// never sent (Overhaul 05 §1, backend services/storyService.js feed map).
  final int? durationSecondsProvided;

  const StoryItem({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    this.caption,
    this.linkedBizId,
    required this.durationSeconds,
    required this.boosted,
    required this.seen,
    required this.createdAt,
    this.durationSecondsProvided,
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
    createdAt:
        DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
    durationSecondsProvided: (j['durationSeconds'] as num?)?.toInt(),
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
    required this.authorId,
    required this.authorUsername,
    this.authorAvatarUrl,
    required this.hasUnseen,
    required this.isBoosted,
    required this.stories,
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
          .map((s) => StoryItem.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Maps a real-rail business-story page onto the single viewer group.
///
/// The rail is GET /api/marketplace/business/:id/stories → {success, stories},
/// each row a Prisma Story plus its poster user. The Story schema carries no
/// mediaType (image URL only), no per-viewer seen state and no boost flag,
/// so items map with the same truthful fallbacks GET /stories/feed uses:
/// IMAGE media, the 5-second image duration, seen=false.
/// [durationSecondsProvided] stays null — the server never sent a duration.
/// Group author is the first poster (the row set's only identity the rail
/// provides); hasUnseen=true reflects that no view record exists for these
/// rows when the ring was tapped.
StoryGroup storyGroupFromBusinessStories(List<BusinessStory> stories) {
  final first = stories.first;
  return StoryGroup(
    authorId: int.tryParse(first.userId) ?? 0,
    authorUsername: first.username ?? '',
    authorAvatarUrl: first.userProfilePictureUrl,
    hasUnseen: true,
    isBoosted: false,
    stories: stories
        .map(
          (s) => StoryItem(
            id: s.id,
            mediaUrl: s.mediaUrl,
            mediaType: 'IMAGE',
            caption: s.caption,
            linkedBizId: s.businessProfileId,
            durationSeconds: 5,
            boosted: false,
            seen: false,
            createdAt: s.createdAt,
            durationSecondsProvided: null,
          ),
        )
        .toList(),
  );
}

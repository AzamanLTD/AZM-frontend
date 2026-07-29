// =============================================================================
// AZAMAN — Story Analytics Screen (Business)
//
// Per-story and aggregate analytics for business stories.
// Shows views, unique viewers, reactions, replies, and viewer list.
//
// Reference: Instagram Story Insights, Snapchat Story Analytics
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/premium_glass_container.dart';

// ── Stats fetch ────────────────────────────────────────────────────────────────

Future<Map<String, dynamic>> _fetchBusinessAnalytics(String businessId) async {
  final res = await apiClient.get('/stories/analytics/business/$businessId');
  if (res.statusCode != 200) return <String, dynamic>{};
  return jsonDecode(res.body) as Map<String, dynamic>;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class StoryAnalyticsScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String businessName;

  const StoryAnalyticsScreen({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  @override
  ConsumerState<StoryAnalyticsScreen> createState() =>
      _StoryAnalyticsScreenState();
}

class _StoryAnalyticsScreenState extends ConsumerState<StoryAnalyticsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _fetchBusinessAnalytics(widget.businessId);
      setState(() { _data = result['data'] as Map<String, dynamic>?; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Story Analytics', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(HugeIconsSolid.arrowReloadHorizontal, color: colors.accent, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _error != null
              ? Center(child: Text('Error: $_error', style: TextStyle(color: colors.danger)))
              : _buildContent(colors),
    );
  }

  Widget _buildContent(AzamanColors colors) {
    final totals = (_data?['totals'] as Map<String, dynamic>?) ?? {};
    final stories = (_data?['stories'] as List? ?? []);

    return RefreshIndicator(
      onRefresh: _load,
      color: colors.accent,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Summary cards ──────────────────────────────────────────────────
          _buildSummaryGrid(colors, totals),
          const SizedBox(height: 20),

          // ── Per-story breakdown ────────────────────────────────────────────
          Text('Per-Story Breakdown', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (stories.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No story data yet. Post a story to see analytics.',
                  style: TextStyle(color: colors.textTertiary), textAlign: TextAlign.center),
            ))
          else
            ...stories.map((s) => _buildStoryCard(s as Map<String, dynamic>, colors)),

          // ── Individual story analytics ──────────────────────────────────────
          if (stories.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Top Viewers', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ..._buildTopViewers(stories, colors),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryGrid(AzamanColors colors, Map<String, dynamic> totals) {
    final stats = [
      {'label': 'Total Views', 'value': totals['totalViews'] ?? 0, 'icon': HugeIconsSolid.search01, 'color': colors.accent},
      {'label': 'Unique Viewers', 'value': totals['totalUniqueViewers'] ?? 0, 'icon': HugeIconsSolid.userGroup, 'color': const Color(0xFF9C59FF)},
      {'label': 'Reactions', 'value': totals['totalReactions'] ?? 0, 'icon': HugeIconsSolid.gift, 'color': const Color(0xFFEF4444)},
      {'label': 'Replies', 'value': totals['totalReplies'] ?? 0, 'icon': HugeIconsSolid.message01, 'color': const Color(0xFF3B97F7)},
      {'label': 'Shares', 'value': totals['totalShares'] ?? 0, 'icon': HugeIconsSolid.sent, 'color': const Color(0xFF10B981)},
      {'label': 'Profile Clicks', 'value': totals['totalProfileClicks'] ?? 0, 'icon': HugeIconsSolid.touchInteraction01, 'color': const Color(0xFFFFD700)},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: stats.length,
      itemBuilder: (_, i) {
        final s = stats[i];
        return PremiumGlassContainer(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(s['icon'] as IconData, color: s['color'] as Color, size: 24),
                const SizedBox(height: 8),
                Text(
                  '${s['value']}',
                  style: TextStyle(color: colors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  s['label'] as String,
                  style: TextStyle(color: colors.textTertiary, fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ).animate().fadeIn(delay: 100.ms * i).scale(begin: const Offset(0.95, 0.95));
      },
    );
  }

  Widget _buildStoryCard(Map<String, dynamic> story, AzamanColors colors) {
    final storyData = (story['story'] as Map<String, dynamic>?) ?? {};
    final mediaUrl = storyData['mediaUrl']?.toString();
    final caption = storyData['caption']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16), bottomLeft: Radius.circular(16),
            ),
            child: SizedBox(
              width: 72, height: 72,
              child: mediaUrl != null
                  ? Image.network(mediaUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: colors.softSurface))
                  : Container(color: colors.softSurface),
            ),
          ),
          // Stats
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (caption != null && caption.isNotEmpty)
                    Text(caption, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _miniStat(colors, HugeIconsSolid.search01, story['viewCount'] ?? 0),
                      const SizedBox(width: 12),
                      _miniStat(colors, HugeIconsSolid.userGroup, story['uniqueViewerCount'] ?? 0),
                      const SizedBox(width: 12),
                      _miniStat(colors, HugeIconsSolid.gift, story['reactionCount'] ?? 0),
                      const SizedBox(width: 12),
                      _miniStat(colors, HugeIconsSolid.message01, story['replyCount'] ?? 0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _miniStat(AzamanColors colors, IconData icon, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.textTertiary),
        const SizedBox(width: 4),
        Text('$count', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  List<Widget> _buildTopViewers(List stories, AzamanColors colors) {
    // Aggregate viewers across all stories
    final viewerMap = <int, Map<String, dynamic>>{};
    for (final s in stories) {
      final viewers = (s['viewers'] as List? ?? []);
      for (final v in viewers) {
        final viewer = v as Map<String, dynamic>;
        final id = viewer['id'] as int;
        if (viewerMap.containsKey(id)) {
          viewerMap[id]!['count'] = (viewerMap[id]!['count'] ?? 0) + 1;
        } else {
          viewerMap[id] = {'username': viewer['username'], 'avatar': viewer['avatar'], 'count': 1};
        }
      }
    }
    final sorted = viewerMap.values.toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    return sorted.take(10).map((v) => ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: colors.softSurface,
        backgroundImage: v['avatar'] != null ? NetworkImage(v['avatar']) : null,
        child: v['avatar'] == null
            ? Text((v['username'] as String?)?[0].toUpperCase() ?? '?',
                style: TextStyle(color: colors.accent))
            : null,
      ),
      title: Text(v['username']?.toString() ?? 'Unknown',
          style: TextStyle(color: colors.textPrimary, fontSize: 14)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: colors.softSurface, borderRadius: BorderRadius.circular(12)),
        child: Text('${v['count']} views',
            style: TextStyle(color: colors.textSecondary, fontSize: 12)),
      ),
    )).toList();
  }
}

// =============================================================================
// AZAMAN — Story Highlights Screen
//
// View, create, and manage permanent story highlight collections.
// Shows highlight circles on profile with cover images.
//
// Reference: Instagram story highlights, Snapchat Spotlight collections
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';

// ── State ─────────────────────────────────────────────────────────────────────

final storyHighlightProvider = StateNotifierProvider.autoDispose
    <StoryHighlightNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return StoryHighlightNotifier()..load();
});

class StoryHighlightNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  StoryHighlightNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await apiClient.get('/stories/highlights');
      if (res.statusCode != 200) throw Exception('Failed');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['data'] as List? ?? [])
          .map((h) => h as Map<String, dynamic>)
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createHighlight(String title, List<int> storyIds) async {
    try {
      await apiClient.post('/stories/highlights', {
        'title': title,
        'storyIds': storyIds,
      });
      await load();
    } catch (_) {}
  }

  Future<void> deleteHighlight(int id) async {
    try {
      await apiClient.delete('/stories/highlights/$id');
      state.whenData((list) {
        state = AsyncValue.data(list.where((h) => h['id'] != id).toList());
      });
    } catch (_) {}
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class StoryHighlightsScreen extends ConsumerStatefulWidget {
  final int? userId;

  const StoryHighlightsScreen({super.key, this.userId});

  @override
  ConsumerState<StoryHighlightsScreen> createState() =>
      _StoryHighlightsScreenState();
}

class _StoryHighlightsScreenState
    extends ConsumerState<StoryHighlightsScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final highlights = ref.watch(storyHighlightProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Highlights', style: TextStyle(color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(HugeIconsSolid.plusSign, color: colors.accent),
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: highlights.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (e, _) => Center(child: Text('Failed to load highlights',
            style: TextStyle(color: colors.textSecondary))),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyState(colors: colors, onCreate: () => _showCreateDialog(context, ref));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) => _HighlightTile(
              highlight: list[i],
              colors: colors,
              onTap: () => _viewHighlight(list[i]),
              onLongPress: () => _showDeleteDialog(list[i]),
            ),
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ref.read(themeProvider).colors.surface,
        title: Text('New Highlight', style: TextStyle(color: ref.read(themeProvider).colors.textPrimary)),
        content: TextField(
          controller: titleCtrl,
          maxLength: 50,
          decoration: InputDecoration(
            hintText: 'Highlight title',
            hintStyle: TextStyle(color: ref.read(themeProvider).colors.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: ref.read(themeProvider).colors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: ref.read(themeProvider).colors.accent),
            ),
          ),
          style: TextStyle(color: ref.read(themeProvider).colors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ref.read(themeProvider).colors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (titleCtrl.text.trim().isNotEmpty) {
                AzamanHaptics.nav();
                ref.read(storyHighlightProvider.notifier)
                    .createHighlight(titleCtrl.text.trim(), []);
                Navigator.pop(ctx);
              }
            },
            child: Text('Create', style: TextStyle(color: ref.read(themeProvider).colors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _viewHighlight(Map<String, dynamic> highlight) {
    // Show a fullscreen viewer for the highlight items
    final items = (highlight['items'] as List? ?? []);
    if (items.isEmpty) return;
    // Navigate to story viewer with highlight items
  }

  void _showDeleteDialog(Map<String, dynamic> highlight) {
    AzamanHaptics.confirm();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ref.read(themeProvider).colors.surface,
        title: Text('Delete highlight?', style: TextStyle(color: ref.read(themeProvider).colors.textPrimary)),
        content: Text('This will permanently remove "${highlight['title']}"',
            style: TextStyle(color: ref.read(themeProvider).colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ref.read(themeProvider).colors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(storyHighlightProvider.notifier)
                  .deleteHighlight(highlight['id']);
              Navigator.pop(ctx);
            },
            child: Text('Delete', style: TextStyle(color: ref.read(themeProvider).colors.danger)),
          ),
        ],
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final AzamanColors colors;
  final VoidCallback onCreate;
  const _EmptyState({required this.colors, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(HugeIconsSolid.star, size: 48, color: colors.textTertiary),
          const SizedBox(height: 12),
          Text('No highlights yet', style: TextStyle(color: colors.textSecondary, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Save your stories to permanent collections',
              style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onCreate,
            icon: Icon(HugeIconsSolid.plusSign, size: 18, color: colors.accent),
            label: Text('New Highlight', style: TextStyle(color: colors.accent)),
          ),
        ],
      ).animate().fadeIn(),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  final Map<String, dynamic> highlight;
  final AzamanColors colors;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _HighlightTile({
    required this.highlight,
    required this.colors,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final items = (highlight['items'] as List? ?? []);
    final coverUrl = items.isNotEmpty
        ? ((items[0] as Map?) ?? {})['mediaUrl']?.toString()
        : highlight['coverUrl']?.toString();

    return GestureDetector(
      onTap: () { AzamanHaptics.nav(); onTap(); },
      onLongPress: onLongPress,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [colors.accent, colors.accent.withValues(alpha: 0.6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: colors.border, width: 2),
            ),
            child: ClipOval(
              child: coverUrl != null && coverUrl.isNotEmpty
                  ? Image.network(coverUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            highlight['title']?.toString() ?? '',
            style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ).animate().fadeIn(delay: 100.ms * (0)),
    );
  }

  Widget _placeholder() {
    return Container(
      color: colors.surface,
      child: Icon(HugeIconsSolid.image02, color: colors.textTertiary, size: 28),
    );
  }
}

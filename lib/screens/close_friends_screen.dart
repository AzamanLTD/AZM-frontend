// =============================================================================
// AZAMAN — Close Friends Management Screen
//
// Manage the private story audience list. Only close friends can see
// stories shared with the "Close Friends" audience.
//
// Reference: Instagram Close Friends, Snapchat Private Story
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

final closeFriendsProvider = StateNotifierProvider.autoDispose
    <CloseFriendsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return CloseFriendsNotifier()..load();
});

class CloseFriendsNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  CloseFriendsNotifier() : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await apiClient.get('/stories/close-friends');
      if (res.statusCode != 200) throw Exception('Failed');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['data'] as List? ?? [])
          .map((f) => f as Map<String, dynamic>)
          .toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addFriend(int friendId) async {
    try {
      await apiClient.post('/stories/close-friends', {'friendId': friendId});
      await load();
    } catch (_) {}
  }

  Future<void> removeFriend(int friendId) async {
    AzamanHaptics.nav();
    try {
      await apiClient.delete('/stories/close-friends/$friendId');
      state.whenData((list) {
        state = AsyncValue.data(list.where((f) => f['id'] != friendId).toList());
      });
    } catch (_) {}
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CloseFriendsScreen extends ConsumerStatefulWidget {
  const CloseFriendsScreen({super.key});

  @override
  ConsumerState<CloseFriendsScreen> createState() => _CloseFriendsScreenState();
}

class _CloseFriendsScreenState extends ConsumerState<CloseFriendsScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await apiClient.get('/contacts?q=$query');
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _searchResults = (body['data'] as List? ?? [])
            .map((c) => c as Map<String, dynamic>)
            .toList();
      });
    } catch (_) {
    } finally {
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final friends = ref.watch(closeFriendsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Close Friends', style: TextStyle(color: colors.textPrimary)),
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search for friends to add...',
                hintStyle: TextStyle(color: colors.textTertiary),
                prefixIcon: Icon(HugeIconsSolid.search01, color: colors.textTertiary, size: 20),
                filled: true,
                fillColor: colors.softSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: TextStyle(color: colors.textPrimary),
            ),
          ),

          // Search results or friends list
          Expanded(
            child: _searchCtrl.text.trim().isNotEmpty
                ? _buildSearchResults(colors)
                : friends.when(
                    loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
                    error: (_, __) => Center(child: Text('Failed to load',
                        style: TextStyle(color: colors.textSecondary))),
                    data: (list) => _buildFriendsList(list, colors),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList(List<Map<String, dynamic>> friends, AzamanColors colors) {
    if (friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(HugeIconsSolid.userGroup, size: 48, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text('No close friends yet', style: TextStyle(color: colors.textSecondary, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Search above to add friends to your private story audience',
                style: TextStyle(color: colors.textTertiary, fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ).animate().fadeIn(),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: friends.length,
      itemBuilder: (_, i) {
        final friend = friends[i];
        return _FriendTile(
          name: friend['username']?.toString() ?? 'Unknown',
          avatarUrl: friend['profilePictureUrl']?.toString(),
          colors: colors,
          onRemove: () => ref.read(closeFriendsProvider.notifier).removeFriend(friend['id']),
        ).animate().fadeIn(delay: 50.ms * i);
      },
    );
  }

  Widget _buildSearchResults(AzamanColors colors) {
    if (_searching) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_searchResults.isEmpty) {
      return Center(child: Text('No results', style: TextStyle(color: colors.textTertiary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (_, i) {
        final contact = _searchResults[i];
        return _SearchResultTile(
          name: contact['username']?.toString() ?? 'Unknown',
          avatarUrl: contact['profilePictureUrl']?.toString(),
          colors: colors,
          onAdd: () {
            AzamanHaptics.nav();
            ref.read(closeFriendsProvider.notifier).addFriend(contact['id']);
            _searchCtrl.clear();
            setState(() => _searchResults = []);
          },
        ).animate().fadeIn(delay: 50.ms * i);
      },
    );
  }
}

class _FriendTile extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final AzamanColors colors;
  final VoidCallback onRemove;

  const _FriendTile({
    required this.name, this.avatarUrl, required this.colors, required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: colors.softSurface,
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
        child: avatarUrl == null
            ? Text(name[0].toUpperCase(), style: TextStyle(color: colors.accent, fontWeight: FontWeight.w600))
            : null,
      ),
      title: Text(name, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500)),
      trailing: IconButton(
        icon: Icon(HugeIconsSolid.cancel01, color: colors.danger, size: 22),
        onPressed: onRemove,
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final AzamanColors colors;
  final VoidCallback onAdd;

  const _SearchResultTile({
    required this.name, this.avatarUrl, required this.colors, required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: colors.softSurface,
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
        child: avatarUrl == null
            ? Text(name[0].toUpperCase(), style: TextStyle(color: colors.accent, fontWeight: FontWeight.w600))
            : null,
      ),
      title: Text(name, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.accent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('Add', style: TextStyle(color: colors.surface, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      onTap: onAdd,
    );
  }
}

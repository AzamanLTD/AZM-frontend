// =============================================================================
// AZAMAN — Forward Message Dialog (Phase 3.3.4)
//
// Shows a bottom sheet to select a conversation to forward a message to.
// Lists friends (direct messages) and groups the user is a member of.
//
// Reference: WhatsApp forward dialog
// =============================================================================

import 'package:flutter/material.dart';
import 'package:azaman/services/api_client.dart';
import 'dart:convert';
import 'package:azaman/services/message_action_service.dart';
import 'package:azaman/widgets/azaman_sheet.dart';
import 'package:azaman/widgets/az_avatar.dart';

class ForwardDialog {
  /// Shows the forward dialog as a modal bottom sheet.
  /// Returns true if the forward was successful.
  static Future<bool> show({
    required BuildContext context,
    required String messageId,
    required String fromContext,
  }) async {
    // Sheet grammar: PANEL. AzSheetGeometry.classify(isScrollable: true) —
    // an unbounded friends+groups list behind a search field, which also
    // drives its own height (it used to fake 0.7 of the screen). The old
    // SizedBox(0.7 * height) and its hand-rolled header + handle are
    // deleted: AzSheetSurface owns radius, surface and the grab handle, and
    // the detents are the weight's own 45%/90%.
    final result = await AzamanSheet.showPanel<bool>(
      context,
      builder: (context, scrollController) => _ForwardSheet(
        messageId: messageId,
        fromContext: fromContext,
        scrollController: scrollController,
      ),
    );
    return result ?? false;
  }
}

class _ForwardSheet extends StatefulWidget {
  final String messageId;
  final String fromContext;

  /// The sheet's own ScrollController. A Panel builder must scroll through
  /// this one — constructing a private ListView controller would silently
  /// detach the drag from the detent.
  final ScrollController scrollController;

  const _ForwardSheet({
    required this.messageId,
    required this.fromContext,
    required this.scrollController,
  });

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _forwarding = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  void _loadConversations() async {
    try {
      // Load friends
      final friendsRes = await ApiClient().get('/api/friends');
      final friends = List<Map<String, dynamic>>.from(jsonDecode(friendsRes.body) as List? ?? []);

      // Load groups
      final groupsRes = await ApiClient().get('/api/groups');
      final groups = List<Map<String, dynamic>>.from(jsonDecode(groupsRes.body) as List? ?? []);

      if (mounted) {
        setState(() {
          _friends = friends;
          _groups = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _forward(String toContext, String toConversationId, String name) async {
    setState(() => _forwarding = true);

    try {
      await MessageActionService.forwardMessage(
        messageId: widget.messageId,
        fromContext: widget.fromContext,
        toContext: toContext,
        toConversationId: toConversationId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Forwarded to $name'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to forward'), backgroundColor: Colors.red),
        );
        setState(() => _forwarding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredFriends = _searchQuery.isEmpty
        ? _friends
        : _friends.where((f) {
            final name = (f['displayName'] ?? f['username'] ?? '').toString().toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    final filteredGroups = _searchQuery.isEmpty
        ? _groups
        : _groups.where((g) {
            final name = (g['name'] ?? '').toString().toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header — the drag handle is gone (the Panel weight draws it).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: [
              Text(
                'Forward to…',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
        ),

        // List — scrolls through the controller the Panel handed us.
        Expanded(
          child: _forwarding
              ? const Center(child: CircularProgressIndicator())
              : _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: widget.scrollController,
                      children: [
                        if (filteredFriends.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Friends',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          ...filteredFriends.map((f) {
                            final name = f['displayName'] ??
                                f['username'] ??
                                'Unknown';
                            final avatar = f['profilePictureUrl'];
                            final friendshipId = f['friendshipId'] ?? f['id'];
                            return ListTile(
                              leading: AzAvatar(
                                circular: true,
                                imageUrl: avatar as String?,
                                name: name.toString(),
                              ),
                              title: Text(name),
                              onTap: () => _forward(
                                'direct',
                                friendshipId.toString(),
                                name.toString(),
                              ),
                            );
                          }),
                        ],
                        if (filteredGroups.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Groups',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          ...filteredGroups.map((g) {
                            final name = g['name'] ?? 'Group';
                            final groupId = g['id'];
                            return ListTile(
                              leading: AzAvatar(
                                circular: true,
                                name: name.toString(),
                              ),
                              title: Text(name.toString()),
                              onTap: () => _forward(
                                'group',
                                groupId.toString(),
                                name.toString(),
                              ),
                            );
                          }),
                        ],
                        if (filteredFriends.isEmpty && filteredGroups.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: Text('No conversations found'),
                            ),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}

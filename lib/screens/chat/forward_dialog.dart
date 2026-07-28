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
import 'package:azaman/services/message_action_service.dart';

class ForwardDialog {
  /// Shows the forward dialog as a modal bottom sheet.
  /// Returns true if the forward was successful.
  static Future<bool> show({
    required BuildContext context,
    required String messageId,
    required String fromContext,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ForwardSheet(
        messageId: messageId,
        fromContext: fromContext,
      ),
    );
    return result ?? false;
  }
}

class _ForwardSheet extends StatefulWidget {
  final String messageId;
  final String fromContext;

  const _ForwardSheet({
    required this.messageId,
    required this.fromContext,
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
      final friendsRes = await ApiClient.dio.get('/api/friends');
      final friends = List<Map<String, dynamic>>.from(friendsRes.data as List? ?? []);

      // Load groups
      final groupsRes = await ApiClient.dio.get('/api/groups');
      final groups = List<Map<String, dynamic>>.from(groupsRes.data as List? ?? []);

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

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Forward to…',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: _forwarding
                ? const Center(child: CircularProgressIndicator())
                : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          if (filteredFriends.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text('Friends',
                                  style: Theme.of(context).textTheme.labelMedium),
                            ),
                            ...filteredFriends.map((f) {
                              final name = f['displayName'] ?? f['username'] ?? 'Unknown';
                              final avatar = f['profilePictureUrl'];
                              final friendshipId = f['friendshipId'] ?? f['id'];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                                  child: avatar == null ? Text(name[0].toUpperCase()) : null,
                                ),
                                title: Text(name),
                                onTap: () => _forward('direct', friendshipId.toString(), name.toString()),
                              );
                            }),
                          ],
                          if (filteredGroups.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text('Groups',
                                  style: Theme.of(context).textTheme.labelMedium),
                            ),
                            ...filteredGroups.map((g) {
                              final name = g['name'] ?? 'Group';
                              final groupId = g['id'];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                  child: Icon(Icons.group, color: Theme.of(context).colorScheme.onSecondaryContainer),
                                ),
                                title: Text(name.toString()),
                                onTap: () => _forward('group', groupId.toString(), name.toString()),
                              );
                            }),
                          ],
                          if (filteredFriends.isEmpty && filteredGroups.isEmpty)
                            const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('No conversations found'))),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

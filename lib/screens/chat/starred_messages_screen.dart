// =============================================================================
// AZAMAN — Starred Messages Screen (Phase 3.3.4)
//
// Shows all starred messages across all conversations.
// Tap to jump to the conversation, long-press to unstar.
//
// Reference: WhatsApp starred messages
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/message_action_service.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';

class StarredMessagesScreen extends ConsumerStatefulWidget {
  const StarredMessagesScreen({super.key});

  @override
  ConsumerState<StarredMessagesScreen> createState() =>
      _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends ConsumerState<StarredMessagesScreen> {
  List<Map<String, dynamic>> _starred = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStarred();
  }

  void _loadStarred() async {
    try {
      final results = await MessageActionService.getStarredMessages();
      if (mounted) setState(() { _starred = results; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _unstar(int index) async {
    final msg = _starred[index];
    final context = msg['context'] as String? ?? 'direct';
    final id = msg['id'] as String?;

    if (id == null) return;

    // Optimistic removal
    setState(() => _starred.removeAt(index));

    try {
      await MessageActionService.toggleStar(context: context, messageId: id);
    } catch (e) {
      // Revert on failure
      if (mounted) setState(() => _starred.insert(index, msg));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Starred Messages')),
      body: AzPullToRefresh(
        onRefresh: () async => _loadStarred(),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _starred.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.star_border_rounded,
                                size: 64, color: Theme.of(context).disabledColor),
                            const SizedBox(height: 16),
                            Text('No starred messages',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text('Long-press a message to star it',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: _starred.length,
                    itemBuilder: (context, index) {
                      final msg = _starred[index];
                      return _StarredItem(
                        message: msg,
                        onUnstar: () => _unstar(index),
                      );
                    },
                  ),
      ),
    );
  }
}

class _StarredItem extends StatelessWidget {
  final Map<String, dynamic> message;
  final VoidCallback onUnstar;

  const _StarredItem({required this.message, required this.onUnstar});

  @override
  Widget build(BuildContext context) {
    final senderName = message['senderName'] as String? ?? 'Unknown';
    final content = message['content'] as String? ?? '';
    final mediaUrl = message['mediaUrl'] as String?;
    final messageType = message['messageType'] as String? ?? 'TEXT';
    final createdAt = DateTime.tryParse(message['createdAt'] as String? ?? '');
    final groupName = message['groupName'] as String?;
    final isMedia = messageType != 'TEXT' || mediaUrl != null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(senderName.isNotEmpty ? senderName[0].toUpperCase() : '?'),
      ),
      title: Row(
        children: [
          Expanded(child: Text(senderName, style: const TextStyle(fontWeight: FontWeight.w600))),
          Icon(Icons.star_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMedia && content.isEmpty)
            const Row(children: [Icon(Icons.image, size: 16), SizedBox(width: 4), Text('Photo')])
          else
            Text(content, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (groupName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(groupName, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
            ),
        ],
      ),
      trailing: createdAt != null
          ? Text(_formatDate(createdAt), style: Theme.of(context).textTheme.bodySmall)
          : null,
      onLongPress: onUnstar,
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) return 'Yesterday';
    else if (diff.inDays < 7) return '${diff.inDays}d';
    else return '${dt.day}/${dt.month}';
  }
}

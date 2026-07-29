// =============================================================================
// AZAMAN — Message Search Screen (Phase 3.3.4)
//
// Full-text search across all chat messages (direct + group).
// Shows results with sender info, message preview, and context.
// Tap a result to jump to the conversation.
//
// Reference: WhatsApp search, Telegram global search
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/message_action_service.dart';

class MessageSearchScreen extends ConsumerStatefulWidget {
  final String? conversationId;
  final String? conversationContext; // 'direct' | 'group' — to scope search

  const MessageSearchScreen({
    super.key,
    this.conversationId,
    this.conversationContext,
  });

  @override
  ConsumerState<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends ConsumerState<MessageSearchScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _controller.text.trim();
    if (query.length < 2) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    _performSearch(query);
  }

  void _performSearch(String query) async {
    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final results = await MessageActionService.searchMessages(
        query: query,
        context: widget.conversationContext ?? 'all',
        conversationId: widget.conversationId,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search messages…',
            border: InputBorder.none,
            hintStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          textInputAction: TextInputAction.search,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _results = [];
                  _hasSearched = false;
                });
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Theme.of(context).disabledColor),
            const SizedBox(height: 16),
            Text('Search across all your chats',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sentiment_dissatisfied,
                size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text('No results found',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final msg = _results[index];
        return _SearchResultItem(message: msg);
      },
    );
  }
}

class _SearchResultItem extends StatelessWidget {
  final Map<String, dynamic> message;

  const _SearchResultItem({required this.message});

  @override
  Widget build(BuildContext context) {
    final senderName = message['senderName'] as String? ?? 'Unknown';
    final content = message['content'] as String? ?? '';
    final mediaUrl = message['mediaUrl'] as String?;
    final messageType = message['messageType'] as String? ?? 'TEXT';
    final createdAt = DateTime.tryParse(message['createdAt'] as String? ?? '');
    final contextType = message['context'] as String? ?? 'direct';
    final groupName = message['groupName'] as String?;
    final isStarred = message['isStarred'] as bool? ?? false;

    final isMedia = messageType != 'TEXT' || mediaUrl != null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              senderName,
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (createdAt != null) ...[
            const SizedBox(width: 8),
            Text(
              _formatDate(createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          if (isMedia) ...[
            Icon(_mediaIcon(messageType), size: 16,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              content.isEmpty && isMedia ? _mediaLabel(messageType) : content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (groupName != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                groupName,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
          if (isStarred) ...[
            const SizedBox(width: 4),
            Icon(Icons.star_rounded,
                size: 14, color: Theme.of(context).colorScheme.primary),
          ],
        ],
      ),
      onTap: () {
        // Navigate to the conversation and scroll to the message
        Navigator.of(context).pop(message);
      },
    );
  }

  IconData _mediaIcon(String type) {
    switch (type) {
      case 'IMAGE': return Icons.image;
      case 'VIDEO': return Icons.videocam;
      case 'AUDIO': return Icons.headphones;
      case 'DOCUMENT': return Icons.description;
      case 'LINK': return Icons.link;
      default: return Icons.attach_file;
    }
  }

  String _mediaLabel(String type) {
    switch (type) {
      case 'IMAGE': return 'Photo';
      case 'VIDEO': return 'Video';
      case 'AUDIO': return 'Voice message';
      case 'DOCUMENT': return 'Document';
      case 'LINK': return 'Link';
      default: return 'Attachment';
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d';
    } else {
      return '${dt.day}/${dt.month}';
    }
  }
}

// =============================================================================
// AZAMAN — Call History Screen
//
// Lists recent calls (voice/video, missed/outgoing/incoming).
// Pulls from backend: GET /api/calls
//
// Reference: WhatsApp Calls tab, Telegram call history
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/api_client.dart';
import 'dart:convert';
import 'package:azaman/screens/call/call_screen.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/staggered_item.dart';

// Provider for call history
final callHistoryProvider = FutureProvider<List<dynamic>>((ref) async {
  final response = await ApiClient().get('/api/calls?limit=50');
  return jsonDecode(response.body)['data'] as List<dynamic>;
});

class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final callsAsync = ref.watch(callHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded),
            onPressed: () => _showNewCallDialog(context),
          ),
        ],
      ),
      body: callsAsync.when(
        loading: () => ListView.builder(
          itemCount: 8,
          itemBuilder: (_, __) => ListTile(
            leading: SkeletonBlock(height: 52, width: 52, borderRadius: BorderRadius.circular(26)),
            title: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: SkeletonBlock(height: 14, width: 140, borderRadius: BorderRadius.circular(4)),
            ),
            subtitle: SkeletonBlock(height: 12, width: 90, borderRadius: BorderRadius.circular(4)),
            trailing: SkeletonBlock(height: 24, width: 24, borderRadius: BorderRadius.circular(12)),
          ),
        ),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('Failed to load calls',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => ref.invalidate(callHistoryProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (calls) {
          if (calls.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_outlined,
                      size: 64, color: Theme.of(context).disabledColor),
                  const SizedBox(height: 16),
                  Text('No call history',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Start a call from any chat',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(callHistoryProvider),
            child: ListView.builder(
              itemCount: calls.length,
              itemBuilder: (context, index) {
                final call = calls[index] as Map<String, dynamic>;
                return StaggeredItem(
                  index: index,
                  child: _CallHistoryItem(call: call),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showNewCallDialog(BuildContext context) {
    // TODO: Show contact picker — for now, navigate to a manual entry
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('New Call'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Enter username or Azaman ID',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                // Navigate to call screen
                // For now, just voice call
                // In production, resolve the username to userId via API
              },
              child: const Text('Call'),
            ),
          ],
        );
      },
    );
  }
}

class _CallHistoryItem extends StatelessWidget {
  final Map<String, dynamic> call;

  const _CallHistoryItem({required this.call});

  @override
  Widget build(BuildContext context) {
    final status = call['status'] as String?;
    final type = call['type'] as String?;
    final caller = call['caller'] as Map<String, dynamic>?;
    final callee = call['callee'] as Map<String, dynamic>?;
    final durationSec = call['durationSec'] as int? ?? 0;
    final createdAt = DateTime.tryParse(call['createdAt'] as String? ?? '');

    // Determine call direction
    final isOutgoing = caller?['id'] != null &&
        caller!['id'].toString() != callee?['id'].toString();

    // Get the "other person" info
    final otherUser = isOutgoing ? callee : caller;
    final name = otherUser?['displayName'] ?? otherUser?['username'] ?? 'Unknown';
    final avatar = otherUser?['profilePictureUrl'] as String?;

    // Call status icon
    IconData statusIcon;
    Color statusColor;
    if (status == 'MISSED') {
      statusIcon = Icons.call_received_rounded;
      statusColor = Colors.red;
    } else if (status == 'REJECTED') {
      statusIcon = Icons.call_received_rounded;
      statusColor = Colors.orange;
    } else if (isOutgoing) {
      statusIcon = Icons.call_made_rounded;
      statusColor = Colors.green;
    } else {
      statusIcon = Icons.call_received_rounded;
      statusColor = Colors.green;
    }

    final isVideo = type == 'VIDEO';

    return ListTile(
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        backgroundImage: avatar != null ? NetworkImage(avatar) : null,
        child: avatar == null
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 20))
            : null,
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: status == 'MISSED' ? FontWeight.w400 : FontWeight.w600,
          color: status == 'MISSED' ? Colors.red : null,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 4),
          if (createdAt != null)
            Text(_formatTimestamp(createdAt),
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 8),
          if (durationSec > 0)
            Text('(${_formatDuration(durationSec)})',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          isVideo ? Icons.videocam_rounded : Icons.call_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        onPressed: () {
          // Re-dial
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CallScreen(
                peerId: otherUser?['id'] ?? 0,
                peerName: name,
                peerAvatar: avatar,
                isVideoCall: isVideo,
                isCaller: true,
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return 'Today, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }

  String _formatDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

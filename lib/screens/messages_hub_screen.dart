import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/personal_chat_interface.dart';
import 'package:azaman/services/api_client.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class PersonalChat {
  final String id;
  final String contactId;
  final String contactAzamanId;
  String contactName;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;

  PersonalChat({
    required this.id,
    required this.contactId,
    required this.contactAzamanId,
    required this.contactName,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });
}

class MessagesHubScreen extends ConsumerStatefulWidget {
  const MessagesHubScreen({super.key});

  @override
  ConsumerState<MessagesHubScreen> createState() => _MessagesHubScreenState();
}

class _MessagesHubScreenState extends ConsumerState<MessagesHubScreen> {
  final List<PersonalChat> _chats = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchChats();
  }

  Future<void> _fetchChats() async {
    setState(() => _isLoading = true);
    try {
      // Renamed from `authProvider` to `auth` to avoid shadowing the
      // top-level Riverpod `authProvider` symbol imported above.
      final auth = ref.read(authProvider);
      final token = auth.user?.token;
      if (token == null) return;

      final response = await apiClient.get('/chat/personal');

      if (response.statusCode == 200 && mounted) {
        final List data = jsonDecode(response.body)['chats'] ?? [];
        setState(() {
          _chats.clear();
          for (final c in data) {
            _chats.add(PersonalChat(
              id: c['id']?.toString() ?? '',
              contactId: c['contactId']?.toString() ?? '',
              contactAzamanId: c['contactAzamanId']?.toString() ?? '',
              contactName: c['contactName']?.toString() ?? 'Unknown',
              lastMessage: c['lastMessage']?.toString(),
              lastMessageTime: c['lastMessageTime'] != null
                  ? DateTime.tryParse(c['lastMessageTime'].toString())
                  : null,
              unreadCount: (c['unreadCount'] as num?)?.toInt() ?? 0,
            ));
          }
        });
      }
    } catch (e) {
      debugPrint('fetch chats error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSearchUserDialog() {
    final colors = ref.read(themeProvider).colors;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Search User',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter Azaman ID',
            hintStyle: TextStyle(color: colors.textTertiary),
            filled: true,
            fillColor: colors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.accent.withValues(alpha: 0.5)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startChatWithUser(controller.text.trim());
            },
            child: Text('Search', style: TextStyle(color: colors.isDark ? Colors.black : Colors.white)),
          ),
        ],
      ),
    ).whenComplete(() {
      // Phase H10 BUGFIX (2026-05-27): controller was allocated above
      // but never disposed. Each open of this dialog leaked one
      // TextEditingController.
      controller.dispose();
    });
  }

  Future<void> _startChatWithUser(String azamanId) async {
    if (azamanId.isEmpty) return;
    final colors = ref.read(themeProvider).colors;
    try {
      final auth = ref.read(authProvider);
      final token = auth.user?.token;
      if (token == null) return;

      final response = await apiClient.post('/chat/personal/start', {'azamanId': azamanId});

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => PersonalChatInterface(
            chatId: data['chatId']?.toString() ?? '',
            contactId: data['contactId']?.toString() ?? '',
            contactAzamanId: azamanId,
            contactName: data['contactName']?.toString() ?? azamanId,
          ),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('User not found'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('start chat error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Failed to start chat'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final p = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $p';
    }
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text('Messages',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: Icon(HugeIconsSolid.refresh01, color: colors.textSecondary),
            onPressed: _fetchChats,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.accent,
        foregroundColor: colors.isDark ? Colors.black : Colors.white,
        onPressed: _showSearchUserDialog,
        child: const Icon(HugeIconsSolid.add01),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(HugeIconsSolid.bubbleChat, size: 64, color: colors.textTertiary),
                      const SizedBox(height: 16),
                      Text('No conversations yet',
                          style: TextStyle(color: colors.textSecondary, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Tap + to start a new chat',
                          style: TextStyle(color: colors.textTertiary, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchChats,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _chats.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: colors.divider),
                    itemBuilder: (context, i) {
                      final chat = _chats[i];
                      return ListTile(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => PersonalChatInterface(
                              chatId: chat.id,
                              contactId: chat.contactId,
                              contactAzamanId: chat.contactAzamanId,
                              contactName: chat.contactName,
                            ),
                          )).then((_) => _fetchChats());
                        },
                        leading: CircleAvatar(
                          backgroundColor: colors.accent.withValues(alpha: 0.2),
                          child: Text(
                            chat.contactName.isNotEmpty
                                ? chat.contactName[0].toUpperCase()
                                : '?',
                            style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(chat.contactName,
                            style: TextStyle(
                                color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                        subtitle: chat.lastMessage != null
                            ? Text(chat.lastMessage!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: colors.textSecondary, fontSize: 13))
                            : null,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatTime(chat.lastMessageTime),
                                style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                            if (chat.unreadCount > 0) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colors.accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('${chat.unreadCount}',
                                    style: TextStyle(
                                        color: colors.isDark ? Colors.black : Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

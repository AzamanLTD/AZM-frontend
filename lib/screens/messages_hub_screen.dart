import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/personal_chat_interface.dart';
import 'package:azaman/services/api_client.dart';


class PersonalChat {
  final String id;
  final String contactId;
  final String contactAzamanId;
  String contactName;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  int unreadCount;

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
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchChats();
  }

  Future<void> _fetchChats() async {
    setState(() => _isLoading = true);
    try {
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
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'New conversation',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter their Azaman ID to start chatting',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'azaman_id',
                    hintStyle: TextStyle(
                      color: colors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 10),
                      child: Icon(
                        Icons.tag,
                        color: colors.textTertiary,
                        size: 18,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _startChatWithUser(controller.text.trim());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Start chat',
                      style: TextStyle(
                        color: colors.isDark ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
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
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    }
    return '${dt.month}/${dt.day}';
  }

  List<PersonalChat> get _filteredChats {
    if (_searchQuery.isEmpty) return _chats;
    final q = _searchQuery.toLowerCase();
    return _chats.where((c) =>
      c.contactName.toLowerCase().contains(q) ||
      (c.lastMessage?.toLowerCase().contains(q) ?? false)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final filtered = _filteredChats;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Messages',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 27,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showSearchUserDialog,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.softSurface,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.edit_outlined,
                        color: colors.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: colors.textTertiary,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search conversations',
                          hintStyle: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colors.accent,
                        strokeWidth: 2,
                      ),
                    )
                  : filtered.isEmpty
                      ? _buildEmptyState(colors)
                      : RefreshIndicator(
                          color: colors.accent,
                          backgroundColor: colors.card,
                          onRefresh: _fetchChats,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                            itemCount: filtered.length,
                            itemBuilder: (context, i) =>
                                _buildChatItem(filtered[i], colors),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AzamanColors colors) {
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search,
                color: colors.textTertiary,
                size: 44,
              ),
              const SizedBox(height: 14),
              Text(
                'No results',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try a different search term',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              color: colors.textTertiary,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              'No conversations yet',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a chat with someone on Azaman',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _showSearchUserDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'New message',
                  style: TextStyle(
                    color: colors.isDark ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(PersonalChat chat, AzamanColors colors) {
    final bool hasUnread = chat.unreadCount > 0;
    final currentUsername = ref.watch(authProvider).user?.username ?? '';
    final bool isMentioned = currentUsername.isNotEmpty &&
        chat.lastMessage != null &&
        chat.lastMessage!.contains('@$currentUsername');

    return Dismissible(
      key: ValueKey('chat_${chat.id}_${chat.unreadCount}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          // Swipe right: mark read
          setState(() {
            chat.unreadCount = 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Marked ${chat.contactName} as read'),
              duration: const Duration(seconds: 1),
            ),
          );
        } else {
          // Swipe left: toggle unread status
          setState(() {
            chat.unreadCount = chat.unreadCount == 0 ? 1 : 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Marked ${chat.contactName} as ${chat.unreadCount > 0 ? "unread" : "read"}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        return false; // Prevent removing tile from list
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.mark_chat_read, color: Colors.white, size: 20),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: colors.accent.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.mark_chat_unread, color: Colors.white, size: 20),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PersonalChatInterface(
              chatId: chat.id,
              contactId: chat.contactId,
              contactAzamanId: chat.contactAzamanId,
              contactName: chat.contactName,
            ),
          )).then((_) => _fetchChats());
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: hasUnread
                ? (isMentioned ? colors.warning.withOpacity(0.08) : colors.accent.withOpacity(0.06))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  chat.contactName.isNotEmpty ? chat.contactName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.contactName,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.lastMessageTime != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(chat.lastMessageTime!),
                            style: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.lastMessage ?? 'No messages yet',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread ? colors.textSecondary : colors.textTertiary,
                              fontSize: 13,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isMentioned ? colors.warning : colors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isMentioned) ...[
                                  Text(
                                    '@',
                                    style: TextStyle(
                                      color: colors.isDark ? Colors.black : Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                Text(
                                  chat.unreadCount > 9 ? '9+' : '${chat.unreadCount}',
                                  style: TextStyle(
                                    color: colors.isDark ? Colors.black : Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

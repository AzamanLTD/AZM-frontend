import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:azaman/config.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:record/record.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/screens/group_chat/group_profile_screen.dart';
import 'package:azaman/screens/susu/susu_dashboard_screen.dart';
import 'package:azaman/widgets/premium_message_bubble.dart';
import 'package:azaman/widgets/premium_chat_input.dart';
import 'package:azaman/providers/premium_chat_provider.dart';
import 'package:azaman/models/chat_message.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/widgets/typing_indicator_bubble.dart';
import 'package:azaman/widgets/chat_date_header.dart';
import 'package:azaman/widgets/disappearing_message_timer_sheet.dart';


class GroupChatScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupChatScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _scrollController = ScrollController();

  bool _sending = false;
  String? _myUserId;
  bool _inputHasText = false;

  // Mention Picker States
  bool _showMentionPicker = false;
  String _mentionFilter = '';

  // Reply States
  ChatMessage? _replyToMessage;

  // Plus menu & typing
  bool _plusMenuOpen = false;
  bool _isTyping = false;



  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _inputHasText) setState(() => _inputHasText = has);
    });
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        ref.read(premiumChatProvider(ChatContextParams(context: ChatContext.group, contextId: widget.groupId)).notifier).loadMessages(loadMore: true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _myUserId = ref.read(authProvider).user?.id?.toString();
    });
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }


  void _onInputChanged() {
    final txt = _input.text;
    final selection = _input.selection;
    if (!selection.isValid) return;
    final caret = selection.end;
    int at = -1;
    for (int i = caret - 1; i >= 0; i--) {
      final ch = txt[i];
      if (ch == ' ' || ch == '\n') break;
      if (ch == '@') {
        at = i;
        break;
      }
    }
    if (at >= 0) {
      final filter = txt.substring(at + 1, caret).toLowerCase();
      setState(() {
        _showMentionPicker = true;
        _mentionFilter = filter;
      });
    } else if (_showMentionPicker) {
      setState(() => _showMentionPicker = false);
    }
  }

  void _insertMention(String username) {
    final txt = _input.text;
    final caret = _input.selection.end;
    int at = -1;
    for (int i = caret - 1; i >= 0; i--) {
      final ch = txt[i];
      if (ch == ' ' || ch == '\n') break;
      if (ch == '@') {
        at = i;
        break;
      }
    }
    if (at >= 0) {
      final before = txt.substring(0, at);
      final after = txt.substring(caret);
      final newText = '$before@$username $after';
      _input.text = newText;
      _input.selection = TextSelection.collapsed(
        offset: at + username.length + 2,
      );
    }
    setState(() => _showMentionPicker = false);
  }

  void _triggerReply(ChatMessage msg) {
    HapticFeedback.lightImpact();
    setState(() => _replyToMessage = msg);
  }

  // Legacy _send() and _sendMessage() have been removed. Sending is handled exclusively by PremiumChatInput via premiumChatProvider.

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final messagesAsync = ref.watch(groupMessagesProvider(widget.groupId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: groupAsync.when(
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
          data: (g) {
            if (g == null) return const SizedBox();
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => GroupProfileScreen(groupId: widget.groupId)),
                );
              },
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: colors.softSurface,
                    backgroundImage: g.avatarUrl != null ? NetworkImage(g.avatarUrl!) : null,
                    child: g.avatarUrl == null
                        ? Text(g.name.substring(0, 1).toUpperCase(), style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name, style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 1.5),
                        Text('${g.members.length} members', style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          Builder(builder: (ctx) {
            final params = ChatContextParams(context: ChatContext.group, contextId: widget.groupId);
            final chatState = ref.watch(premiumChatProvider(params));
            return IconButton(
              icon: Icon(Icons.timer_outlined,
                  size: 20,
                  color: chatState.disappearAfterSeconds != null
                      ? colors.accent
                      : colors.textSecondary),
              tooltip: chatState.disappearAfterSeconds != null
                  ? 'Disappearing: ${chatState.disappearLabel}'
                  : 'Disappearing messages',
              onPressed: () => showDisappearTimerSheet(context, params),
            );
          }),
        ],
      ),
      body: Column(
        children: [
          _SusuBanner(groupId: widget.groupId),
          Expanded(
            child: Builder(
              builder: (ctx) {
                final params = ChatContextParams(context: ChatContext.group, contextId: widget.groupId);
                final chatState = ref.watch(premiumChatProvider(params));
                
                if (chatState.isLoading && chatState.messages.isEmpty) {
                  return Center(child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2));
                }
                
                if (chatState.messages.isEmpty) {
                  return Center(child: Text('No messages here yet.', style: TextStyle(color: colors.textTertiary, fontSize: 13)));
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(top: 12, bottom: 20),
                  itemCount: chatState.messages.length + (chatState.hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == chatState.messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2))
                      );
                    }
                    final msg = chatState.messages[i];
                    if (msg.kind == MessageKind.susuEvent) {
                      return _SusuEventCard(message: msg, colors: colors);
                    }
                    final msgDate = msg.timestamp;
                    final prevMsg = i < chatState.messages.length - 1 ? chatState.messages[i + 1] : null;
                    final showDateHeader = prevMsg == null ||
                        msgDate.day != prevMsg.timestamp.day ||
                        msgDate.month != prevMsg.timestamp.month;

                    return Column(children: [
                      if (showDateHeader) ChatDateHeader(date: msgDate),
                      PremiumMessageBubble(
                        key: ValueKey(msg.localId),
                        message: msg,
                        myUserId: int.tryParse(_myUserId ?? '0') ?? 0,
                        showAvatar: true,
                        showSenderName: true,
                        onReply: (m) => setState(() => _replyToMessage = m),
                        onReact: (id, emoji) => ref.read(premiumChatProvider(params).notifier).reactToMessage(id, emoji),
                        onEdit: (m) => _showEditDialog(context, colors, m, params),
                        onDelete: (id) => ref.read(premiumChatProvider(params).notifier).deleteMessage(id),
                        onRetry: () => ref.read(premiumChatProvider(params).notifier).retryMessage(msg.localId),
                      )
                    ]);
                  },
                );
              }
            ),
          ),
          
          Builder(
            builder: (ctx) {
              final chatState = ref.watch(premiumChatProvider(ChatContextParams(context: ChatContext.group, contextId: widget.groupId)));
              if (chatState.typingUserIds.isNotEmpty) return TypingBubble(colors: colors);
              return const SizedBox();
            }
          ),

          if (_showMentionPicker)
            groupAsync.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (g) {
                if (g == null) return const SizedBox();
                final filtered = g.members
                    .where((m) => (m.username ?? '').toLowerCase().contains(_mentionFilter))
                    .take(5)
                    .toList();
                if (filtered.isEmpty) return const SizedBox();
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.divider, width: 0.7),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: filtered
                        .map((m) => InkWell(
                              onTap: () => _insertMention(m.username ?? ''),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 13,
                                      backgroundColor: colors.accent.withValues(alpha: 0.15),
                                      child: Text((m.username ?? '?').substring(0, 1).toUpperCase(), style: TextStyle(color: colors.accent, fontSize: 10, fontWeight: FontWeight.w800)),
                                    ),
                                    const SizedBox(width: 10),
                                    Text('@${m.username ?? 'unknown'}', style: TextStyle(color: colors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                    const Spacer(),
                                    if (m.role == 'ADMIN')
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(color: colors.warning.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(4)),
                                        child: Text('ADMIN', style: TextStyle(color: colors.warning, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                                      ),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                );
              },
            ),

          Builder(
            builder: (ctx) {
              final params = ChatContextParams(context: ChatContext.group, contextId: widget.groupId);
              return PremiumChatInput(
                controller: _input,
                focusNode: _focusNode,
                replyTo: _replyToMessage,
                onClearReply: () => setState(() => _replyToMessage = null),
                onSendText: (text) {
                  ref.read(premiumChatProvider(params).notifier).sendTextMessage(
                    text,
                    replyToId: _replyToMessage?.id,
                    replyToText: _replyToMessage?.text,
                    replyToSenderName: _replyToMessage?.senderUsername,
                  );
                  setState(() => _replyToMessage = null);
                },
                onSendMedia: ({required mediaUrl, required mediaType, required messageType, mimeType, size, duration, waveformPeaks, linkPreview, caption}) {
                  ref.read(premiumChatProvider(params).notifier).sendMediaMessage(
                    mediaUrl: mediaUrl, mediaType: mediaType, messageType: messageType, mimeType: mimeType,
                    size: size, duration: duration, waveformPeaks: waveformPeaks, linkPreview: linkPreview, caption: caption,
                  );
                },
                onTypingChanged: (isTyping) => ref.read(premiumChatProvider(params).notifier).sendTyping(isTyping),
              );
            }
          ),
        ],
      ),
    );
  }


  void _showEditDialog(BuildContext ctx, AzamanColors c, ChatMessage msg, ChatContextParams params) {
    final editCtrl = TextEditingController(text: msg.text);
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        title: Text('Edit Message', style: TextStyle(color: c.textPrimary, fontSize: 16)),
        content: TextField(
          controller: editCtrl, maxLines: null,
          style: TextStyle(color: c.textPrimary),
          decoration: InputDecoration(hintText: 'Edit your message', hintStyle: TextStyle(color: c.textTertiary)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: c.textTertiary))),
          TextButton(
            onPressed: () {
              final newText = editCtrl.text.trim();
              if (newText.isNotEmpty) {
                ref.read(premiumChatProvider(params).notifier).editMessage(msg.id, newText);
              }
              Navigator.pop(ctx);
            },
            child: Text('Save', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
  }
}

class _SusuEventCard extends StatelessWidget {
  final ChatMessage message; final AzamanColors colors;
  const _SusuEventCard({required this.message, required this.colors});
  @override
  Widget build(BuildContext context) {
    final meta = message.metadata ?? {};
    final type = meta['type']?.toString() ?? 'SUSU_EVENT';
    final icon = type == 'SUSU_PAYOUT' ? '💸' : type == 'SUSU_CYCLE_COMPLETE' ? '🏆' : '✅';
    final label = meta['label']?.toString() ?? type.replaceFirst('_', ' ');
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.accent.withValues(alpha: 0.2))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: colors.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
  
class _SusuBanner extends ConsumerWidget {
  final String groupId;
  const _SusuBanner({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final statusAsync = ref.watch(susuInitiationStatusProvider(groupId));
    final init = statusAsync.valueOrNull;
    if (init == null || init.susuGroupId == null) return const SizedBox();

    if (init.isActive) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SusuDashboardScreen(susuId: init.susuGroupId!),
            ),
          );
        },
        child: Container(
          color: colors.accent.withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.volunteer_activism, color: colors.accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Active Susu cycle in progress',
                  style: TextStyle(color: colors.accent, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right, color: colors.accent, size: 16),
            ],
          ),
        ),
      );
    }
    return const SizedBox();
  }
}

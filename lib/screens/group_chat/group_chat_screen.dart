// =============================================================================
// GROUP CHAT SCREEN  (Master Sprint, 2026-05-27)
//
// Slim group chat surface: scrollable message list + composer. Reuses
// patterns from the existing personal chat. Susu binding shows a top
// banner that links to the susu dashboard.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:cached_network_image/cached_network_image.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/group_chat/group_profile_screen.dart';
import 'package:azaman/screens/susu/susu_dashboard_screen.dart';
import 'package:azaman/widgets/chat_plus_menu.dart';


class GroupChatScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupChatScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _input = TextEditingController();
  final _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  bool _sending = false;

  // Master Sprint v2: @-mentions overlay state. When the user types `@`
  // we show a member picker; tapping inserts `@username` at the cursor.
  bool _showMentionPicker = false;
  String _mentionFilter = '';

  GroupMessage? _replyToMessage;
  final Map<String, DateTime> _typingMembers = {};

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final txt = _input.text;
    final selection = _input.selection;
    if (!selection.isValid) return;
    final caret = selection.end;
    // Look back from the caret for an `@` token that hasn't been
    // closed by a space yet.
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
      if (txt[i] == '@') {
        at = i;
        break;
      }
    }
    if (at < 0) return;
    final replacement = '@$username ';
    final next = txt.replaceRange(at, caret, replacement);
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + replacement.length),
    );
    setState(() => _showMentionPicker = false);
  }

  Future<void> _pickImage() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles();
  }

  void _showStickerSheet() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stickers coming soon')),
    );
  }

  Widget _buildGroupTypingIndicator(AzamanColors colors) {
    String label;
    final names = _typingMembers.keys.take(3).toList();
    if (names.isEmpty) return const SizedBox();
    if (names.length == 1) {
      label = '$names is typing…';
    } else if (names.length == 2) {
      label = '${names[0]} and ${names[1]} are typing…';
    } else {
      label = 'Several people are typing…';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 5,
            backgroundColor: colors.accent,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(DateTime date, AzamanColors colors) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(date.year, date.month, date.day);
    final diff = today.difference(msgDate).inDays;
    String label;
    if (diff == 0) label = 'Today';
    else if (diff == 1) label = 'Yesterday';
    else label = intl.DateFormat('EEE d MMM').format(date);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
          style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final txt = _input.text.trim();
    if (txt.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(groupActionsProvider).sendMessage(widget.groupId, content: txt);
      _input.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final msgsAsync = ref.watch(groupMessagesProvider(widget.groupId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: groupAsync.when(
          loading: () => const Text(''),
          error: (_, __) => const Text('Group'),
          data: (g) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupProfileScreen(groupId: widget.groupId),
                ),
              ).then((_) {
                ref.invalidate(groupDetailProvider(widget.groupId));
                ref.invalidate(susuInitiationStatusProvider(widget.groupId));
              });
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    g?.name ?? 'Group',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800),
                  ),
                ),
                Icon(Icons.arrow_downward,
                    color: colors.textTertiary, size: 18),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Group profile',
            icon: Icon(Icons.group_outlined, color: colors.accent, size: 20),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupProfileScreen(groupId: widget.groupId),
                ),
              ).then((_) {
                ref.invalidate(groupDetailProvider(widget.groupId));
                ref.invalidate(susuInitiationStatusProvider(widget.groupId));
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Susu state banner: shows the initiation countdown while
          // configuring, or the active-dashboard link once activated.
          _SusuBanner(groupId: widget.groupId),
          Expanded(
            child: msgsAsync.when(
              loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
              error: (e, _) => Center(child: Text(e.toString())),
              data: (msgs) {
                if (msgs.isEmpty && _typingMembers.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet — say hi!',
                      style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                  );
                }
                final sorted = List<GroupMessage>.from(msgs)
                  ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                final typingCount = _typingMembers.length;
                final totalItems = sorted.length + (typingCount > 0 ? 1 : 0);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: totalItems,
                  itemBuilder: (context, i) {
                    if (typingCount > 0 && i == sorted.length) {
                      return _buildGroupTypingIndicator(colors);
                    }
                    final msg = sorted[i];
                    final prevMsg = i > 0 ? sorted[i - 1] : null;
                    if (prevMsg != null) {
                      final diff = msg.createdAt.difference(prevMsg.createdAt);
                      if (diff.inDays >= 1) {
                        return Column(
                          children: [
                            _buildDateChip(msg.createdAt, colors),
                            const SizedBox(height: 8),
                            _MessageBubble(
                              msg: msg,
                              colors: colors,
                              showAvatar: true,
                              showSenderName: true,
                              onLongPress: () {},
                            ),
                          ],
                        );
                      }
                      final sameSender = msg.senderId == prevMsg.senderId;
                      final closeEnough = diff.inMinutes < 2;
                      return _MessageBubble(
                        msg: msg,
                        colors: colors,
                        showAvatar: !(sameSender && closeEnough),
                        showSenderName: !(sameSender && closeEnough),
                        onLongPress: () {},
                      );
                    }
                    return _MessageBubble(
                      msg: msg,
                      colors: colors,
                      showAvatar: true,
                      showSenderName: true,
                      onLongPress: () {},
                    );
                  },
                );
              },
            ),
          ),
          // Master Sprint v2: @-mentions picker. Slides up above the
          // composer when the user is mid-mention, lists matching members.
          if (_showMentionPicker)
            groupAsync.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (g) {
                if (g == null) return const SizedBox();
                final filtered = g.members
                    .where((m) =>
                        (m.username ?? '').toLowerCase().contains(_mentionFilter))
                    .take(5)
                    .toList();
                if (filtered.isEmpty) return const SizedBox();
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colors.accent.withOpacity(0.15),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        (m.username ?? '?').substring(0, 1).toUpperCase(),
                                        style: TextStyle(
                                          color: colors.accent,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '@${m.username ?? 'unknown'}',
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (m.role == 'ADMIN')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: colors.warning.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'ADMIN',
                                          style: TextStyle(
                                            color: colors.warning,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
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
          _Composer(
            controller: _input,
            focusNode: _focusNode,
            sending: _sending,
            onSend: _send,
            colors: colors,
            onImageTap: _pickImage,
            onDocumentTap: _pickDocument,
            onStickerTap: _showStickerSheet,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final GroupMessage msg;
  final AzamanColors colors;
  final bool showAvatar;
  final bool showSenderName;
  final VoidCallback? onLongPress;

  const _MessageBubble({
    required this.msg,
    required this.colors,
    this.showAvatar = true,
    this.showSenderName = true,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (msg.type == 'SYSTEM') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            msg.content ?? '',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    final isMine = msg.senderId == 'me';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar)
            CircleAvatar(
              radius: 14,
              backgroundColor: colors.accent.withOpacity(0.15),
              backgroundImage: null,
              child: Text(
                      (msg.senderUsername ?? '?').substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
            )
          else
            const SizedBox(width: 28),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMine ? colors.accent.withOpacity(0.15) : colors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.divider, width: 0.6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showSenderName && !isMine)
                      Text(
                        msg.senderUsername ?? 'Unknown',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    if (showSenderName && !isMine)
                      const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                        ),
                        children: _buildBodySpans(msg.content ?? '', colors),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final AzamanColors colors;
  final VoidCallback? onImageTap;
  final VoidCallback? onDocumentTap;
  final VoidCallback? onStickerTap;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.colors,
    this.onImageTap,
    this.onDocumentTap,
    this.onStickerTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        color: Colors.transparent,
        child: Row(
          children: [
            ChatPlusMenu(
              onImageTap: onImageTap,
              onDocumentTap: onDocumentTap,
              onStickerTap: onStickerTap,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.divider),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Message…  type @ to mention',
                    hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12.5),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: sending ? null : onSend,
              icon: Icon(Icons.send_outlined, color: colors.accent),
            ),
          ],
        ),
      ),
    );
  }
}


/// Master Sprint v2: tokenise message body so `@username` substrings render
/// in the accent color. Reused by group + (future) ticket message bubbles.
List<InlineSpan> _buildBodySpans(String text, AzamanColors colors) {
  final spans = <InlineSpan>[];
  final regex = RegExp(r'@\w+');
  int cursor = 0;
  for (final m in regex.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start)));
    }
    spans.add(TextSpan(
      text: m.group(0)!,
      style: TextStyle(
        color: colors.accent,
        fontWeight: FontWeight.w800,
      ),
    ));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}

// =============================================================================
// SUSU BANNER — Phase 5 / Workstream D (2026-06-01)
//
// Sits below the chat AppBar. Three states:
//   • no susu        → renders nothing
//   • CONFIGURING    → live countdown banner with chevron-expandable details
//                      (per-cycle, projected pool, frequency) + ready count
//   • ACTIVE         → tap-to-open the Susu dashboard
//
// The countdown ticks every second locally; the underlying status refreshes
// from susuInitiationStatusProvider (also nudged by socket events the chat
// screen already listens to via the group room).
// =============================================================================
class _SusuBanner extends ConsumerStatefulWidget {
  final String groupId;
  const _SusuBanner({required this.groupId});

  @override
  ConsumerState<_SusuBanner> createState() => _SusuBannerState();
}

class _SusuBannerState extends ConsumerState<_SusuBanner> {
  Timer? _ticker;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // 1s tick to animate the countdown. Cheap — only rebuilds this banner.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmtCountdown(Duration d) {
    if (d.isNegative) return 'expired';
    final days = d.inDays;
    final h = d.inHours % 24;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (days > 0) return '${days}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final statusAsync = ref.watch(susuInitiationStatusProvider(widget.groupId));
    final rate = ref.watch(susuSuppliedRateProvider).valueOrNull;
    final init = statusAsync.valueOrNull;
    if (init == null || init.susuGroupId == null) return const SizedBox();

    // ── Active susu → dashboard link ──────────────────────────────────────
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
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.success.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: colors.success.withOpacity(0.30), width: 0.7),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_outlined,
                  color: colors.success, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Susu active · tap to view cycles & payouts',
                  style: TextStyle(
                      color: colors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.arrow_forward, color: colors.success, size: 14),
            ],
          ),
        ),
      );
    }

    // ── Configuring → countdown banner ────────────────────────────────────
    if (!init.isConfiguring) return const SizedBox();
    final deadline = init.deadline;
    final remaining =
        deadline == null ? Duration.zero : deadline.difference(DateTime.now());
    final ghsRate = rate?.usdcToGhs ?? 0;
    final contribution = init.contributionUsdc ?? 0;
    final pool = init.projectedPoolUsdc;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      decoration: BoxDecoration(
        color: colors.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.warning.withOpacity(0.30), width: 0.7),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.access_time, color: colors.warning, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Susu initiating · verify in ${_fmtCountdown(remaining)}',
                      style: TextStyle(
                        color: colors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${init.readyCount}/${init.memberCount}',
                    style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700),
                  ),
                  Icon(
                    _expanded
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    color: colors.warning,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: colors.divider, height: 12),
                  _detail(colors, 'Per cycle',
                      '\$${contribution.toStringAsFixed(2)}'
                      '${ghsRate > 0 ? '  ≈ GH₵ ${(contribution * ghsRate).toStringAsFixed(2)}' : ''}'),
                  _detail(colors, 'Projected pool / cycle',
                      '\$${pool.toStringAsFixed(2)}'
                      '${ghsRate > 0 ? '  ≈ GH₵ ${(pool * ghsRate).toStringAsFixed(2)}' : ''}'),
                  _detail(colors, 'Frequency', init.frequency ?? '—'),
                  _detail(colors, 'Members', '${init.memberCount}'),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                GroupProfileScreen(groupId: widget.groupId),
                          ),
                        );
                      },
                      icon: Icon(Icons.task_alt_outlined,
                          size: 14, color: colors.warning),
                      label: Text('View members & verification',
                          style: TextStyle(
                              color: colors.warning,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: colors.warning.withOpacity(0.40)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detail(AzamanColors colors, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: TextStyle(color: colors.textTertiary, fontSize: 11)),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

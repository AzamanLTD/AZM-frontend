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
  GroupMessage? _replyToMessage;

  // Plus menu & typing
  bool _plusMenuOpen = false;
  bool _isTyping = false;

  // Telegram recording states
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _recordLocked = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  Timer? _waveTimer;
  double _recordingDragY = 0.0;
  List<double> _waveformPeaks = [];

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _inputHasText) setState(() => _inputHasText = has);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _myUserId = ref.read(authProvider).user?.id?.toString();
      _scrollToBottom();
    });
    _simulateTypingIndicator();
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _waveTimer?.cancel();
    _audioRecorder.dispose();
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

  void _simulateTypingIndicator() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isTyping = true);
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _isTyping = false);
        });
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

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final filename = 'voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
        final path = '${dir.path}/$filename';

        HapticFeedback.mediumImpact();
        setState(() {
          _isRecording = true;
          _recordDuration = 0;
          _recordLocked = false;
          _recordingDragY = 0.0;
          _waveformPeaks = List.generate(30, (_) => 0.1);
        });

        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) setState(() => _recordDuration++);
        });

        _waveTimer = Timer.periodic(const Duration(milliseconds: 70), (timer) {
          if (mounted) {
            setState(() {
              _waveformPeaks.removeAt(0);
              _waveformPeaks.add(0.1 + math.Random().nextDouble() * 0.8);
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _recordTimer?.cancel();
    _waveTimer?.cancel();
    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);

    if (send && path != null) {
      _sendMessage(type: 'audio', mediaUrl: path, text: 'Voice note (${_formatDuration(_recordDuration)})');
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _triggerReply(GroupMessage msg) {
    HapticFeedback.lightImpact();
    setState(() => _replyToMessage = msg);
  }

  Future<void> _send() async {
    final txt = _input.text.trim();
    if (txt.isEmpty) return;
    _input.clear();
    await _sendMessage(text: txt, type: 'TEXT');
  }

  Future<void> _sendMessage({required String text, String? mediaUrl, String type = 'TEXT'}) async {
    if (_sending) return;
    setState(() => _sending = true);
    
    final metadata = {
      if (_replyToMessage != null) 'replyToId': _replyToMessage!.id,
      if (_replyToMessage != null) 'replyToText': _replyToMessage!.content,
      if (_replyToMessage != null) 'replyToSenderName': _replyToMessage!.senderUsername ?? 'Member',
    };

    try {
      await ref.read(groupActionsProvider).sendMessage(
        widget.groupId,
        content: text,
        type: type,
        media: mediaUrl,
        metadata: metadata,
      );
      setState(() => _replyToMessage = null);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

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
      ),
      body: Column(
        children: [
          _SusuBanner(groupId: widget.groupId),
          Expanded(
            child: messagesAsync.when(
              loading: () => Center(child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2)),
              error: (err, _) => Center(child: Text('Error loading messages: $err', style: TextStyle(color: colors.danger))),
              data: (msgs) {
                if (msgs.isEmpty) {
                  return Center(
                    child: Text('No messages here yet.', style: TextStyle(color: colors.textTertiary, fontSize: 13)),
                  );
                }
                
                // Ensure messages are sorted chronologically oldest first
                final sortedMsgs = List<GroupMessage>.from(msgs)
                  ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  itemCount: sortedMsgs.length,
                  itemBuilder: (context, i) {
                    final msg = sortedMsgs[i];
                    final isMe = msg.senderId?.toString() == _myUserId;
                    return Dismissible(
                      key: ValueKey('reply_${msg.id}'),
                      direction: DismissDirection.startToEnd,
                      confirmDismiss: (dir) async {
                        _triggerReply(msg);
                        return false;
                      },
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 16),
                        child: Icon(Icons.reply, color: colors.accent, size: 20),
                      ),
                      child: _MessageBubble(
                        msg: msg,
                        isMe: isMe,
                        colors: colors,
                        onMentionTap: (uname) {
                          _input.text = '${_input.text}@$uname ';
                          _focusNode.requestFocus();
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Someone is typing', style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    _BouncingDotsVisualizer(colors: colors),
                  ],
                ),
              ),
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
                                      backgroundColor: colors.accent.withOpacity(0.15),
                                      child: Text((m.username ?? '?').substring(0, 1).toUpperCase(), style: TextStyle(color: colors.accent, fontSize: 10, fontWeight: FontWeight.w800)),
                                    ),
                                    const SizedBox(width: 10),
                                    Text('@${m.username ?? 'unknown'}', style: TextStyle(color: colors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                    const Spacer(),
                                    if (m.role == 'ADMIN')
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(color: colors.warning.withOpacity(0.10), borderRadius: BorderRadius.circular(4)),
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

          _buildInputBar(colors),
        ],
      ),
    );
  }

  Widget _buildInputBar(AzamanColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply Preview Block
        if (_replyToMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: colors.surface, border: Border(top: BorderSide(color: colors.divider, width: 0.5))),
            child: Row(
              children: [
                Icon(Icons.reply, color: colors.accent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Replying to ${_replyToMessage!.senderUsername ?? 'Member'}', style: TextStyle(color: colors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(_replyToMessage!.content ?? 'Media note', style: TextStyle(color: colors.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _replyToMessage = null),
                  child: Icon(Icons.close, color: colors.textTertiary, size: 16),
                ),
              ],
            ),
          ),
        
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5)),
          ),
          padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Plus menu
              GestureDetector(
                onTap: () => setState(() => _plusMenuOpen = !_plusMenuOpen),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: _plusMenuOpen ? colors.accent.withOpacity(0.12) : colors.softSurface,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(_plusMenuOpen ? Icons.close : Icons.add, color: _plusMenuOpen ? colors.accent : colors.textSecondary, size: 20),
                ),
              ),
              const SizedBox(width: 8),

              // Recording Panel
              if (_isRecording)
                Expanded(child: _buildAudioRecordingBar(colors))
              else
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(color: colors.softSurface, borderRadius: BorderRadius.circular(22)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _input,
                      focusNode: _focusNode,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message… type @ to mention',
                        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14, fontWeight: FontWeight.w500),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),

              // Mic / Send button (Telegram Style with floating lock layout)
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    onLongPressStart: (_) {
                      if (!_inputHasText) _startRecording();
                    },
                    onLongPressMoveUpdate: (details) {
                      if (_isRecording && !_recordLocked) {
                        setState(() {
                          _recordingDragY = details.localPosition.dy;
                          if (_recordingDragY < -65.0) {
                            _recordLocked = true;
                            HapticFeedback.heavyImpact();
                          }
                        });
                      }
                    },
                    onLongPressEnd: (_) {
                      if (_isRecording && !_recordLocked) {
                        _stopRecording(send: true);
                      }
                    },
                    onTap: () {
                      if (_inputHasText) {
                        _send();
                      } else if (_isRecording && _recordLocked) {
                        _stopRecording(send: true);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 38, height: 38,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: (_inputHasText || _recordLocked) ? colors.accent : colors.softSurface,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _inputHasText
                            ? Icons.send_outlined
                            : (_recordLocked ? Icons.send_outlined : Icons.mic),
                        color: (_inputHasText || _recordLocked)
                            ? (colors.isDark ? Colors.black : Colors.white)
                            : colors.textTertiary,
                        size: 18,
                      ),
                    ),
                  ),
                  if (_isRecording && !_recordLocked)
                    Positioned(
                      bottom: 50,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, color: colors.accent, size: 16),
                          const SizedBox(height: 2),
                          Icon(Icons.keyboard_arrow_up, color: colors.accent, size: 12),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Plus Menu Panel (excl. crypto transactions to keep it simple for groups)
        if (_plusMenuOpen) _buildPlusMenuPanel(colors),
      ],
    );
  }

  Widget _buildAudioRecordingBar(AzamanColors colors) {
    return Container(
      height: 38,
      decoration: BoxDecoration(color: colors.softSurface, borderRadius: BorderRadius.circular(22)),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_formatDuration(_recordDuration), style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Expanded(child: _LockedWaveformVisualizer(peaks: _waveformPeaks, color: colors.accent)),
          if (!_recordLocked)
            Row(
              children: [
                Icon(Icons.keyboard_double_arrow_left_outlined, color: colors.textTertiary, size: 14),
                const SizedBox(width: 2),
                Text('Slide to cancel', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              ],
            )
          else
            GestureDetector(
              onTap: () => _stopRecording(send: false),
              child: Icon(HugeIconsStroke.delete01, color: colors.danger, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildPlusMenuPanel(AzamanColors colors) {
    return Container(
      height: 120,
      decoration: BoxDecoration(color: colors.surface, border: Border(top: BorderSide(color: colors.divider, width: 0.8))),
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _plusMediaItem(colors, HugeIconsStroke.image01, 'Photos', _pickImage),
          _plusMediaItem(colors, Icons.emoji_emotions_outlined, 'Stickers', _showStickerSheet),
          _plusMediaItem(colors, HugeIconsStroke.folder01, 'Document', _pickDocument),
          _plusMediaItem(colors, HugeIconsStroke.location01, 'Location', () {}),
        ],
      ),
    );
  }

  Widget _plusMediaItem(AzamanColors colors, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: colors.softSurface, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.textPrimary, size: 20),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _pickImage() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      _sendMessage(type: 'image', mediaUrl: file.path, text: 'Sent a photo');
    }
  }

  void _pickDocument() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      _sendMessage(type: 'document', mediaUrl: result.files.single.path!, text: 'Sent a document');
    }
  }

  void _showStickerSheet() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stickers coming soon')));
  }
}

// Typing indicators
class _BouncingDotsVisualizer extends StatefulWidget {
  final AzamanColors colors;
  const _BouncingDotsVisualizer({required this.colors});

  @override
  State<_BouncingDotsVisualizer> createState() => _BouncingDotsVisualizerState();
}

class _BouncingDotsVisualizerState extends State<_BouncingDotsVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (idx) {
          final delay = idx * 0.2;
          final value = math.sin((_controller.value * 2 * math.pi) + delay);
          final offset = (value + 1.0) * 3.0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Transform.translate(
              offset: Offset(0, -offset),
              child: Container(
                width: 5, height: 5,
                decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _LockedWaveformVisualizer extends StatelessWidget {
  final List<double> peaks;
  final Color color;
  const _LockedWaveformVisualizer({required this.peaks, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 24),
      painter: _WaveformPainter(peaks: peaks, color: color),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final Color color;
  _WaveformPainter({required this.peaks, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final double spacing = size.width / peaks.length;
    for (int i = 0; i < peaks.length; i++) {
      final double x = i * spacing;
      final double h = size.height * peaks[i];
      final double y1 = (size.height - h) / 2;
      final double y2 = y1 + h;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _MessageBubble extends StatelessWidget {
  final GroupMessage msg;
  final bool isMe;
  final AzamanColors colors;
  final Function(String username)? onMentionTap;

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    required this.colors,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    final String time = intl.DateFormat('h:mm a').format(msg.createdAt);
    final String sender = msg.senderUsername ?? 'Member';

    final Color bubbleColor = isMe ? colors.accent : colors.softSurface;
    final Color textColor = isMe ? (colors.isDark ? Colors.black : Colors.white) : colors.textPrimary;
    final Color metaColor = isMe ? (colors.isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.7)) : colors.textTertiary;

    // Fetch reply tags from message metadata
    final replyToId = msg.metadata?['replyToId']?.toString();
    final replyToText = msg.metadata?['replyToText']?.toString();
    final replyToSenderName = msg.metadata?['replyToSenderName']?.toString();

    final bubbleWidget = Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sender display name for other group members
          if (!isMe) ...[
            Text(
              sender,
              style: TextStyle(color: colors.accent, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
          ],

          // Reply Preview inside Group Bubble
          if (replyToId != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: (isMe ? Colors.black : Colors.white).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border(left: BorderSide(color: isMe ? Colors.white : colors.accent, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(replyToSenderName ?? 'Reply', style: TextStyle(color: isMe ? Colors.white : colors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(replyToText ?? '', style: TextStyle(color: textColor.withOpacity(0.85), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),

          // If audio
          if (msg.type == 'audio' && msg.mediaUrl != null)
            SizedBox(
              width: 190,
              child: _AudioPlayerBubble(
                path: msg.mediaUrl!,
                isMe: isMe,
                colors: colors,
              ),
            )
          else if (msg.type == 'image' && msg.mediaUrl != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(msg.mediaUrl!, fit: BoxFit.cover),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Spacer(),
                    Text(time, style: TextStyle(color: metaColor, fontSize: 9.5, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            )
          else
            Text.rich(
              TextSpan(
                children: [
                  ..._buildBodySpans(msg.content ?? '', colors),
                  const TextSpan(text: '   '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Text(time, style: TextStyle(color: metaColor, fontSize: 9.5, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500, height: 1.35),
            ),
        ],
      ),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: colors.accent.withOpacity(0.12),
              child: Text(
                sender.isNotEmpty ? sender[0].toUpperCase() : '?',
                style: TextStyle(color: colors.accent, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
          ],
          bubbleWidget,
        ],
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
            border: Border.all(color: colors.success.withOpacity(0.30), width: 0.7),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_outlined, color: colors.success, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Susu active · tap to view cycles & payouts',
                  style: TextStyle(color: colors.success, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.arrow_forward, color: colors.success, size: 14),
            ],
          ),
        ),
      );
    }

    return const SizedBox();
  }
}

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
      style: TextStyle(color: colors.accent, fontWeight: FontWeight.w800),
    ));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}

class _AudioPlayerBubble extends StatefulWidget {
  final String path;
  final bool isMe;
  final AzamanColors colors;
  const _AudioPlayerBubble({required this.path, required this.isMe, required this.colors});

  @override
  State<_AudioPlayerBubble> createState() => _AudioPlayerBubbleState();
}

class _AudioPlayerBubbleState extends State<_AudioPlayerBubble> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _ensurePlayer() async {
    if (_player != null) return;
    final p = AudioPlayer();
    _player = p;
    _positionSub = p.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _stateSub = p.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playing = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _position = Duration.zero;
            _playing = false;
          }
        });
      }
    });
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    await _ensurePlayer();
    final p = _player!;
    if (_playing) {
      await p.pause();
      return;
    }
    setState(() => _loading = true);
    try {
      if (_position == Duration.zero) {
        final path = widget.path;
        Source source;
        if (path.startsWith('http://') || path.startsWith('https://')) {
          source = UrlSource(path);
        } else if (path.startsWith('/') || path.startsWith('file://')) {
          final cleanPath = path.startsWith('file://') ? path.substring(7) : path;
          source = DeviceFileSource(cleanPath);
        } else {
          source = UrlSource('${AppConfig.baseUrl}$path');
        }
        await p.play(source);
      } else {
        await p.resume();
      }
      final dur = await p.getDuration();
      if (mounted && dur != null) {
        setState(() => _duration = dur);
      }
    } catch (e) {
      debugPrint('Audio playback error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDuration(Duration d) {
    final m = (d.inSeconds ~/ 60).toString();
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isMe
        ? (widget.colors.isDark ? Colors.black87 : Colors.white)
        : widget.colors.textPrimary;
    final progress = (_duration != null && _duration!.inMilliseconds > 0)
        ? (_position.inMilliseconds / _duration!.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: textColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(color: textColor, strokeWidth: 1.5),
                  )
                : Icon(_playing ? Icons.pause : Icons.play_arrow, color: textColor, size: 18),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: textColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: textColor,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _duration != null ? _formatDuration(_position) + ' / ' + _formatDuration(_duration!) : '0:00',
                style: TextStyle(color: textColor.withOpacity(0.65), fontSize: 9.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

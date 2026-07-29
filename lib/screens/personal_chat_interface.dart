import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:azaman/config.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/screens/tickets/ticket_create_sheet.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/providers/ticket_provider.dart';
import 'package:azaman/widgets/chat_money_card.dart';
import 'package:azaman/widgets/chat_transfer_sheet.dart';
import 'package:azaman/widgets/active_ticket_hud.dart';
import 'package:azaman/services/pdf_receipt_service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/models/chat_message.dart';

class PersonalChatInterface extends ConsumerStatefulWidget {
  final String chatId;
  final String contactId;
  final String contactAzamanId;
  final String contactName;

  const PersonalChatInterface({
    super.key,
    required this.chatId,
    required this.contactId,
    required this.contactAzamanId,
    required this.contactName,
  });

  @override
  ConsumerState<PersonalChatInterface> createState() => _PersonalChatInterfaceState();
}

class _PersonalChatInterfaceState extends ConsumerState<PersonalChatInterface>
    with SingleTickerProviderStateMixin {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FocusNode _inputFocus = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();

  final List<ChatMessage> _messages = [];
  bool _isLoading = true;
  String _nickname = '';
  bool _inputHasText = false;

  // Premium feature states
  ChatMessage? _replyToMessage;
  bool _isTyping = false;
  bool _plusMenuOpen = false;

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
    _chatController.addListener(() {
      final has = _chatController.text.trim().isNotEmpty;
      if (has != _inputHasText) setState(() => _inputHasText = has);
    });
    _fetchMessages();
    _simulateTypingIndicator();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _recordTimer?.cancel();
    _waveTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  // Simulate typing indicator for a premium live feel
  void _simulateTypingIndicator() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isTyping = true);
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _isTyping = false);
        });
      }
    });
  }


  /// Parse a string type from the API into a MessageKind.
  static MessageKind _parseKind(String t) {
    switch (t.toUpperCase()) {
      case 'IMAGE': case 'IMAGE_PROOF': return MessageKind.image;
      case 'VIDEO': return MessageKind.video;
      case 'AUDIO': return MessageKind.audio;
      case 'DOCUMENT': return MessageKind.document;
      case 'LINK': return MessageKind.link;
      case 'STICKER': return MessageKind.sticker;
      case 'SYSTEM': case 'SYSTEM_URGENCY': return MessageKind.system;
      case 'PAYMENT_TRANSFER': return MessageKind.transaction;
      case 'TRANSFER_SENT': case 'TRANSFER_COMPLETED': case 'TRANSFER_DECLINED':
        return MessageKind.peerTransfer;
      case 'TRANSFER_REQUEST': return MessageKind.transferRequest;
      case 'TEXT': case '': return MessageKind.text;
      default: return MessageKind.text;
    }
  }

  Future<void> _fetchMessages() async {
    setState(() => _isLoading = true);
    try {
      final auth = ref.read(authProvider);
      final response = await apiClient.get('/friends/chat/${widget.chatId}/messages');

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final List rawMessages = data['messages'] ?? [];
        
        // Sort chronologically (oldest first, newest at the bottom of the list)
        final sortedRaw = List.from(rawMessages);
        sortedRaw.sort((a, b) {
          final da = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime.now();
          final db = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime.now();
          return da.compareTo(db);
        });

        setState(() {
          _messages.clear();
          for (final m in sortedRaw) {
            final senderId = m['senderId']?.toString() ?? '';
            final currentUserId = auth.user?.id.toString() ?? '';
            final meta = m['metadata'] != null ? m['metadata'] as Map<String, dynamic> : null;
            _messages.add(ChatMessage(
              id: m['id']?.toString() ?? '',
              localId: m['localId']?.toString() ?? m['id']?.toString() ?? '',
              senderId: senderId,
              isMe: senderId == currentUserId,
              text: m['text']?.toString() ?? m['content']?.toString() ?? '',
              mediaUrl: m['mediaUrl']?.toString(),
              kind: _parseKind(m['messageType']?.toString() ?? m['type']?.toString() ?? 'TEXT'),
              status: MessageStatus.read,
              timestamp: m['createdAt'] != null
                  ? DateTime.tryParse(m['createdAt'].toString()) ?? DateTime.now()
                  : DateTime.now(),
              amount: (m['cryptoAmount'] as num?)?.toDouble() ?? (meta?['amount'] as num?)?.toDouble(),
              currency: m['cryptoCurrency']?.toString() ?? meta?['currency']?.toString(),
              metadata: {
                if (m['cryptoCompleted'] == true || meta?['status'] == 'COMPLETED')
                  'completed': true,
                if (meta != null) ...meta,
              },
              replyToId: meta?['replyToId']?.toString(),
              replyToText: meta?['replyToText']?.toString(),
              replyToSenderName: meta?['replyToSenderName']?.toString(),
            ));
            // DEBUG: Log EVERY message's raw keys and parsed type
            print('DEBUG MSG #${_messages.length}: raw keys=${m.keys.toList()}, m[type]=${m['type']}, m[messageType]=${m['messageType']}, parsed_type=${_messages.last.kind}, content_preview=${(m['content']?.toString() ?? m['text']?.toString() ?? '').substring(0, (m['content']?.toString() ?? m['text']?.toString() ?? '').length.clamp(0, 40))}');
          }
          _nickname = data['nickname']?.toString() ?? '';
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('fetch messages error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  String get _displayName => _nickname.isNotEmpty ? _nickname : widget.contactName;

  Future<void> _saveNickname(String nickname) async {
    try {
      await apiClient.put('/chat/personal/${widget.chatId}/nickname', {'nickname': nickname});
    } catch (e) {
      debugPrint('save nickname error: $e');
    }
  }

  // Telegram recording implementation
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

  void _triggerReply(ChatMessage msg) {
    HapticFeedback.lightImpact();
    setState(() => _replyToMessage = msg);
  }

  Future<void> _sendTextMessage() async {
    final txt = _chatController.text.trim();
    if (txt.isEmpty) return;
    _chatController.clear();
    await _sendMessage(text: txt, type: 'text');
  }

  Future<void> _openTransferSheet({bool initialIsRequest = false}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChatTransferSheet(contactName: widget.contactName, initialIsRequest: initialIsRequest),
    );

    if (result == null) return;
    
    final double amount = result['amount'] as double;
    final bool isRequest = result['isRequest'] as bool;

    if (amount <= 0) return;

    if (!isRequest) {
      final bool authenticated = await _authenticateBiometric();
      if (!authenticated || !mounted) return;
    }

    _executeCryptoTransfer(amount, isRequest: isRequest);
  }

  Future<bool> _authenticateBiometric() async {
    final colors = ref.read(themeProvider).colors;
    try {
      final bool canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) {
        final bool deviceSupport = await _localAuth.isDeviceSupported();
        if (!deviceSupport) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Biometrics not available on this device'),
              backgroundColor: colors.danger,
              behavior: SnackBarBehavior.floating,
            ));
          }
          return false;
        }
      }

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate to send crypto to $_displayName',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!didAuthenticate && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Authentication failed'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }

      return didAuthenticate;
    } catch (e) {
      debugPrint('biometric auth error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Biometric authentication error'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return false;
    }
  }

  Future<void> _executeCryptoTransfer(double amount, {bool isRequest = false}) async {
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isRequest ? 'Sending request...' : 'Processing transfer...'),
      backgroundColor: colors.accent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 1),
    ));

    final auth = ref.read(authProvider);

    try {
      final token = auth.user?.token;
      if (token == null) return;

      final endpoint = isRequest 
          ? '/friends/transfer/request' 
          : '/friends/transfer/send';

      final body = isRequest 
          ? {
              'friendshipId': widget.chatId,
              'amount': amount,
              'reference': 'Request for $amount USDC'
            }
          : {
              'friendshipId': widget.chatId,
              'amount': amount,
              'reference': 'Transfer $amount USDC'
            };

      final response = await apiClient.post(endpoint, body);

      final bool completed = response.statusCode == 200 || response.statusCode == 201;

      if (mounted) {
        final cryptoMsg = ChatMessage(
          id: 'crypto_${DateTime.now().microsecondsSinceEpoch}',
          localId: 'crypto_${DateTime.now().microsecondsSinceEpoch}',
          senderId: ref.read(authProvider).user?.id.toString() ?? '',
          isMe: true,
          text: isRequest ? 'Requested $amount USDC' : 'Sent $amount USDC',
          kind: isRequest ? MessageKind.transferRequest : MessageKind.transaction,
          timestamp: DateTime.now(),
          status: completed ? MessageStatus.sent : MessageStatus.failed,
          amount: amount,
          currency: 'USDC',
          metadata: {'completed': completed && !isRequest},
        );
        setState(() => _messages.add(cryptoMsg));
        _scrollToBottom();
        
        // Wait, the API for transfer already sends the message! 
        // For TRANSFER_REQUEST we just sent the message manually.
        // For PAYMENT_TRANSFER, the /transfer endpoint automatically broadcasted a DirectMessage in the backend.
        // Let's rely on Socket to receive the actual message from the server, but keep the optimistic update.

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(completed
              ? (isRequest ? 'Request sent!' : '\$$amount sent successfully!')
              : (isRequest ? 'Failed to send request.' : 'Transfer failed. Please try again.')),
          backgroundColor: completed ? colors.success : colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('transfer error: $e');
      if (mounted) {
        final cryptoMsg = ChatMessage(
          id: 'crypto_${DateTime.now().microsecondsSinceEpoch}',
          localId: 'crypto_${DateTime.now().microsecondsSinceEpoch}',
          senderId: ref.read(authProvider).user?.id.toString() ?? '',
          isMe: true,
          text: isRequest ? 'Requested $amount USDC' : 'Sent $amount USDC',
          kind: isRequest ? MessageKind.transferRequest : MessageKind.transaction,
          timestamp: DateTime.now(),
          status: MessageStatus.failed,
          amount: amount,
          currency: 'USDC',
          metadata: null,
        );
        setState(() => _messages.add(cryptoMsg));
        _scrollToBottom();

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Action failed. Please try again.'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _sendMessage({required String text, String? mediaUrl, required String type}) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final auth = ref.read(authProvider);
    
    final msg = ChatMessage(
      id: tempId,
      localId: tempId,
      senderId: ref.read(authProvider).user?.id.toString() ?? '',
      isMe: true,
      text: text,
      mediaUrl: mediaUrl,
      kind: _parseKind(type),
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      replyToId: _replyToMessage?.id,
      replyToText: _replyToMessage?.text,
      replyToSenderName: _replyToMessage != null
          ? (_replyToMessage!.isMe ? 'You' : widget.contactName)
          : null,
    );

    setState(() {
      _messages.add(msg);
      _replyToMessage = null;
    });
    _scrollToBottom();

    try {
      final response = await apiClient.post('/friends/chat/${widget.chatId}/messages', {
        'text': text,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        'type': type,
        'metadata': {
          if (msg.replyToId != null) 'replyToId': msg.replyToId,
          if (msg.replyToText != null) 'replyToText': msg.replyToText,
          if (msg.replyToSenderName != null) 'replyToSenderName': msg.replyToSenderName,
        }
      });

      if (response.statusCode == 201 && mounted) {
        final data = jsonDecode(response.body);
        final idx = _messages.indexOf(msg);
        if (idx != -1) {
          setState(() {
            _messages[idx] = ChatMessage(
              id: data['message']?['id']?.toString() ?? tempId,
              localId: tempId,
              senderId: ref.read(authProvider).user?.id.toString() ?? '',
              isMe: true,
              text: data['message']?['text']?.toString() ?? text,
              mediaUrl: data['message']?['mediaUrl']?.toString(),
              kind: _parseKind(data['message']?['type']?.toString() ?? type),
              status: MessageStatus.sent,
              timestamp: data['message']?['createdAt'] != null
                  ? DateTime.tryParse(data['message']['createdAt'].toString()) ?? DateTime.now()
                  : DateTime.now(),
              replyToId: msg.replyToId,
              replyToText: msg.replyToText,
              replyToSenderName: msg.replyToSenderName,
            );
          });
        }
      } else if (mounted) {
        setState(() => msg.status = MessageStatus.failed);
      }
    } catch (e) {
      if (mounted) setState(() => msg.status = MessageStatus.failed);
    }
  }

  void _showChatProfileSheet() {
    final colors = ref.read(themeProvider).colors;
    HapticFeedback.selectionClick();
    
    // Extract shared photos from messages
    final mediaMessages = _messages.where((m) => m.kind == MessageKind.image || m.mediaUrl != null).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
          decoration: BoxDecoration(
            color: colors.isDark ? Colors.black.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.90),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: colors.textTertiary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              
              // Profile Circle
              CircleAvatar(
                radius: 46,
                backgroundColor: colors.accent.withValues(alpha: 0.12),
                child: Text(
                  _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
                  style: TextStyle(color: colors.accent, fontSize: 36, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              
              Text(_displayName, style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('@${widget.contactAzamanId}', style: TextStyle(color: colors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              
              const SizedBox(height: 24),
              
              // Settings list
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.divider, width: 0.8),
                  ),
                  child: Column(
                    children: [
                      _profileActionRow(colors, HugeIconsStroke.pencilEdit01, 'Edit Nickname', () {
                        Navigator.pop(ctx);
                        _showNicknameDialog();
                      }),
                      Divider(height: 1, color: colors.divider),
                      _profileActionRow(colors, HugeIconsStroke.alertSquare, 'Mute Notifications', () {}),
                      Divider(height: 1, color: colors.divider),
                      _profileActionRow(colors, Icons.block, 'Block User', () {}, isDestructive: true),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Shared media section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Text('SHARED MEDIA', style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                    ),
                    Expanded(
                      child: mediaMessages.isEmpty
                          ? Center(child: Text('No media shared yet', style: TextStyle(color: colors.textTertiary, fontSize: 13)))
                          : GridView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: mediaMessages.length,
                              itemBuilder: (context, idx) {
                                final url = mediaMessages[idx].mediaUrl;
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    color: colors.softSurface,
                                    child: url != null && url.startsWith('http')
                                        ? Image.network(url, fit: BoxFit.cover)
                                        : Icon(Icons.insert_drive_file_outlined, color: colors.textTertiary),
                                  ),
                                );
                              },
                            ),
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

  Widget _profileActionRow(AzamanColors colors, IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? colors.danger : colors.textPrimary, size: 20),
      title: Text(title, style: TextStyle(color: isDestructive ? colors.danger : colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
      trailing: Icon(Icons.chevron_right, color: colors.textTertiary, size: 16),
      onTap: onTap,
    );
  }

  void _showNicknameDialog() {
    final colors = ref.read(themeProvider).colors;
    final controller = TextEditingController(text: _nickname);
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, decoration: BoxDecoration(color: colors.textTertiary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('Edit nickname', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: -0.4)),
              const SizedBox(height: 6),
              Text('Set a custom name for ${widget.contactName}', style: TextStyle(color: colors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(color: colors.softSurface, borderRadius: BorderRadius.circular(14)),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Nickname',
                    hintStyle: TextStyle(color: colors.textTertiary, fontWeight: FontWeight.w500),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () {
                    final nick = controller.text.trim();
                    if (nick.isNotEmpty) {
                      setState(() => _nickname = nick);
                      _saveNickname(nick);
                    }
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(20)),
                    alignment: Alignment.center,
                    child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    // ── Fetch open tickets for this friendship (for the HUD) ────────────────
    final ticketState = ref.watch(ticketDashboardProvider(widget.chatId));
    final openTickets = ticketState.openTickets;

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(colors),
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2))
                    : _messages.isEmpty
                        ? _buildEmptyChat(colors)
                        : ListView.builder(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final msg = _messages[i];
                              return Dismissible(
                                key: ValueKey('reply_${msg.id}'),
                                direction: DismissDirection.startToEnd,
                                confirmDismiss: (dir) async {
                                  _triggerReply(msg);
                                  return false; // Snaps back, does not delete
                                },
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 16),
                                  child: Icon(Icons.reply, color: colors.accent, size: 20),
                                ),
                                child: Column(
                                  children: [
                                    if (_shouldShowDateHeader(i))
                                      _buildDateHeader(msg.timestamp, colors),
                                    if (const [MessageKind.peerTransfer, MessageKind.transaction, MessageKind.transferRequest].contains(msg.kind))
                                      _transactionBubble(msg, colors)
                                    else if ((msg.kind == MessageKind.image || msg.kind == MessageKind.image) && msg.mediaUrl != null && msg.mediaUrl!.contains(','))
                                      _slantedStackBubble(msg, colors)
                                    else
                                      _textBubble(msg, colors),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              
              if (_isTyping) _buildTypingDots(colors),
              _buildInputBar(colors),
            ],
          ),

          // ── Active Ticket HUD — draggable right-edge indicator ────────────
          if (openTickets.isNotEmpty)
            ActiveTicketHud(
              tickets: openTickets,
              peerName: widget.contactName,
              onTap: (ticket) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TicketWorkspaceScreen(
                      ticketId: ticket.id,
                      friendUsername: widget.contactName,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTypingDots(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.contactName} is typing', style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            _BouncingDotsVisualizer(colors: colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AzamanColors colors) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 14, 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary, size: 20),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _showChatProfileSheet,
              child: CircleAvatar(
                radius: 19,
                backgroundColor: colors.softSurface,
                child: Text(
                  _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _showChatProfileSheet,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName,
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text('Online', style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: _showEscrowInstructions,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Icon(Icons.confirmation_number_outlined, color: colors.accent, size: 12),
                    const SizedBox(width: 4),
                    Text('TICKET', style: TextStyle(color: colors.accent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: colors.softSurface, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(Icons.more_vert, color: colors.textSecondary, size: 18),
              ),
              color: colors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 6,
              onSelected: (value) {
                switch (value) {
                  case 'profile':
                    _showChatProfileSheet();
                    break;
                  case 'search':
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Search in conversation — coming soon')),
                    );
                    break;
                  case 'mute':
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${_displayName} muted')),
                    );
                    break;
                  case 'block':
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: colors.card,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Text('Block ${_displayName}?', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                        content: Text('They won\'t be able to message you. You can unblock from your settings.', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: colors.textTertiary))),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_displayName} blocked')));
                            },
                            child: Text('Block', style: TextStyle(color: colors.danger)),
                          ),
                        ],
                      ),
                    );
                    break;
                  case 'report':
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: colors.card,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Text('Report ${_displayName}?', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                        content: Text('We\'ll review this conversation and take action if guidelines are violated.', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: colors.textTertiary))),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted. Thank you.')));
                            },
                            child: Text('Report', style: TextStyle(color: colors.danger)),
                          ),
                        ],
                      ),
                    );
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'profile',
                  child: Row(children: [Icon(Icons.person_outline, size: 18, color: colors.textPrimary), const SizedBox(width: 12), Text('View Profile', style: TextStyle(color: colors.textPrimary, fontSize: 13))]),
                ),
                PopupMenuItem(
                  value: 'search',
                  child: Row(children: [Icon(Icons.search, size: 18, color: colors.textPrimary), const SizedBox(width: 12), Text('Search', style: TextStyle(color: colors.textPrimary, fontSize: 13))]),
                ),
                PopupMenuItem(
                  value: 'mute',
                  child: Row(children: [Icon(Icons.notifications_off_outlined, size: 18, color: colors.textPrimary), const SizedBox(width: 12), Text('Mute Notifications', style: TextStyle(color: colors.textPrimary, fontSize: 13))]),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Row(children: [Icon(Icons.block, size: 18, color: colors.danger), const SizedBox(width: 12), Text('Block', style: TextStyle(color: colors.danger, fontSize: 13))]),
                ),
                PopupMenuItem(
                  value: 'report',
                  child: Row(children: [Icon(Icons.flag_outlined, size: 18, color: colors.danger), const SizedBox(width: 12), Text('Report', style: TextStyle(color: colors.danger, fontSize: 13))]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChat(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: colors.softSurface,
            child: Text(
              _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 22),
            ),
          ),
          const SizedBox(height: 14),
          Text(_displayName, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: -0.3)),
          const SizedBox(height: 4),
          Text('Send a message to start the conversation', style: TextStyle(color: colors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildDateHeader(DateTime dt, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: colors.softSurface.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
          child: Text(_formatDateHeader(dt), style: TextStyle(color: colors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _textBubble(ChatMessage msg, AzamanColors colors) {
    final bool isMe = msg.isMe;
    final bubbleColor = isMe ? colors.accent : colors.softSurface;
    final textColor = isMe ? (colors.isDark ? Colors.black : Colors.white) : colors.textPrimary;
    final metaColor = isMe ? (colors.isDark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.7)) : colors.textTertiary;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
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
            // Reply Preview Inside Bubble
            if (msg.replyToId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (isMe ? Colors.black : Colors.white).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border(left: BorderSide(color: isMe ? Colors.white : colors.accent, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(msg.replyToSenderName ?? 'Reply', style: TextStyle(color: isMe ? Colors.white : colors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(msg.replyToText ?? '', style: TextStyle(color: textColor.withValues(alpha: 0.85), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),

            // If it's an audio message note, show play button and wave
            if (msg.kind == MessageKind.audio && msg.mediaUrl != null)
              SizedBox(
                width: 190,
                child: _AudioPlayerBubble(
                  path: msg.mediaUrl!,
                  isMe: isMe,
                  colors: colors,
                ),
              )
            else if (msg.kind == MessageKind.image && msg.mediaUrl != null)
              // Thin-ring image bubble: edge-to-edge image, accent border,
              // floating timestamp chip in the bottom-right corner so the image
              // fills the bubble with no dead space.
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.accent.withValues(alpha: 0.35), width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.network(
                        msg.mediaUrl!,
                        fit: BoxFit.cover,
                        width: 240,
                        errorBuilder: (_, __, ___) => Container(
                          width: 240, height: 160,
                          color: colors.card,
                          child: Icon(Icons.image_not_supported_outlined, color: colors.textTertiary, size: 32),
                        ),
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : Container(
                                width: 240, height: 160,
                                color: colors.card,
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent)),
                              ),
                      ),
                    ),
                  ),
                  // Floating time + status chip
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_formatMessageTime(msg.timestamp),
                              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w500)),
                          if (isMe) ...[
                            const SizedBox(width: 3),
                            _statusIcon(msg.status, colors),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: msg.text + '   ',
                      style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500, height: 1.35),
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_formatMessageTime(msg.timestamp), style: TextStyle(color: metaColor, fontSize: 9.5, fontWeight: FontWeight.w500)),
                          if (isMe) ...[
                            const SizedBox(width: 3),
                            _statusIcon(msg.status, colors),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Spacer(),
                if (msg.kind != MessageKind.text && msg.kind != MessageKind.image) ...[
                  Text(_formatMessageTime(msg.timestamp), style: TextStyle(color: metaColor, fontSize: 10, fontWeight: FontWeight.w500)),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _statusIcon(msg.status, colors),
                  ],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slantedStackBubble(ChatMessage msg, AzamanColors colors) {
    final isMe = msg.isMe;
    final urls = msg.mediaUrl?.split(',') ?? [];
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            width: 200,
            height: 170,
            child: _SlantedMediaStack(imageUrls: urls),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(_formatMessageTime(msg.timestamp), style: TextStyle(color: colors.textTertiary, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _transactionBubble(ChatMessage msg, AzamanColors colors) {
    final currentUser = ref.read(authProvider).user;
    final myAzmId = currentUser?.azamanId ?? '';

    // Derive card status from messageType
    final String cardStatus;
    if (msg.kind == MessageKind.peerTransfer || (msg.metadata?['completed'] == true)) {
      cardStatus = 'completed';
    } else if (msg.kind == MessageKind.transferRequest) {
      cardStatus = 'pending';
    } else if (msg.kind == MessageKind.peerTransfer) {
      cardStatus = 'failed';
    } else {
      cardStatus = (msg.metadata?['completed'] == true) ? 'completed' : 'failed';
    }

    return ChatMoneyCard(
      amount: msg.amount ?? 0,
      currency: msg.currency ?? 'USDC',
      isMe: msg.isMe,
      contactName: widget.contactName,
      status: cardStatus,
      isRequest: msg.kind == MessageKind.transferRequest,
      reference: msg.id,
      memo: msg.text.contains('Sent') || msg.text.contains('Received') || msg.text.contains('Requested') ? null : msg.text,
      timestamp: msg.timestamp,
      onDownloadReceipt: (msg.metadata?['completed'] == true) ? () async {
        try {
          await PdfReceiptService.instance.shareTransferReceipt(
            referenceId: msg.id,
            amount: msg.amount ?? 0,
            currency: msg.currency ?? 'USDC',
            fromAzmId: msg.isMe ? myAzmId : widget.contactAzamanId,
            toName: msg.isMe ? widget.contactName : 'You',
            toAzmId: msg.isMe ? widget.contactAzamanId : myAzmId,
            timestamp: msg.timestamp,
            completed: (msg.metadata?['completed'] == true),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not generate receipt: \$e')),
            );
          }
        }
      } : null,
    );
  }

  Widget _statusIcon(MessageStatus status, AzamanColors colors) {
    if (status == MessageStatus.sending) {
      return SizedBox(
        width: 10, height: 10,
        child: CircularProgressIndicator(color: colors.isDark ? Colors.black : Colors.white, strokeWidth: 1.2),
      );
    }
    if (status == MessageStatus.sent) {
      return Icon(Icons.check, color: colors.isDark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.7), size: 11);
    }
    if (status == MessageStatus.read) {
      return Icon(Icons.done_all, color: colors.isDark ? Colors.black : Colors.white, size: 12);
    }
    return Icon(Icons.error_outline, color: colors.danger, size: 12);
  }

  Widget _buildInputBar(AzamanColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply Box Indicator
        if (_replyToMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.reply, color: colors.accent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _replyToMessage!.isMe ? 'Replying to Yourself' : 'Replying to ${widget.contactName}',
                        style: TextStyle(color: colors.accent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _replyToMessage!.text,
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                    color: _plusMenuOpen ? colors.accent.withValues(alpha: 0.12) : colors.softSurface,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _plusMenuOpen ? Icons.close : Icons.add,
                    color: _plusMenuOpen ? colors.accent : colors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Text Field & Recording Strip Stack (Telegram-style overlay)
              Expanded(
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    // Always render the text field to preserve layout height and focus
                    Opacity(
                      opacity: _isRecording ? 0.0 : 1.0,
                      child: IgnorePointer(
                        ignoring: _isRecording,
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 120),
                          decoration: BoxDecoration(color: colors.softSurface, borderRadius: BorderRadius.circular(22)),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _chatController,
                            focusNode: _inputFocus,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                            onSubmitted: (_) => _sendTextMessage(),
                            decoration: InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 15, fontWeight: FontWeight.w500),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Recording Strip overlay
                    if (_isRecording)
                      Positioned.fill(
                        child: _buildAudioRecordingBar(colors),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Mic / Send button (Telegram Lock Audio Recorder with floating lock layout)
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
                        _sendTextMessage();
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

        // Animated Plus Menu
        if (_plusMenuOpen) _buildPlusMenuPanel(colors),
      ],
    );
  }

  Widget _buildAudioRecordingBar(AzamanColors colors) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colors.softSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(_formatDuration(_recordDuration), style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Expanded(
            child: _LockedWaveformVisualizer(peaks: _waveformPeaks, color: colors.accent),
          ),
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
      height: 200,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider, width: 0.8)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Transaction shortcuts (Glowing card layout)
          Row(
            children: [
              Expanded(
                child: _plusTransactionBtn(colors, 'Send USDC', HugeIconsSolid.moneySend01, Colors.green, () {
                  setState(() => _plusMenuOpen = false);
                  _openTransferSheet(initialIsRequest: false);
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _plusTransactionBtn(colors, 'Request', HugeIconsSolid.moneyReceive01, colors.accent, () {
                  setState(() => _plusMenuOpen = false);
                  _openTransferSheet(initialIsRequest: true);
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _plusTransactionBtn(colors, 'Create Ticket', Icons.confirmation_number_outlined, Colors.amber, () {
                  setState(() => _plusMenuOpen = false);
                  _showEscrowInstructions();
                }),
              ),
            ],
          ),
          const Spacer(),
          // Media / Sticker grid below
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _plusMediaItem(colors, HugeIconsStroke.image01, 'Photos', _pickImage),
              _plusMediaItem(colors, Icons.emoji_emotions_outlined, 'Stickers', _showStickerSheet),
              _plusMediaItem(colors, HugeIconsStroke.folder01, 'Document', _pickDocument),
              _plusMediaItem(colors, HugeIconsStroke.location01, 'Location', () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _plusTransactionBtn(AzamanColors colors, String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _plusMediaItem(AzamanColors colors, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: colors.softSurface, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: colors.textPrimary, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showEscrowInstructions() {
    // Open the premium ticket create sheet directly.
    // The old multi-step "how escrow works" screen is replaced by
    // the inline escrow toggle in the new TicketCreateSheet.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(ctx).padding.top + 40,
        ),
        child: TicketCreateSheet(
          friendshipId: widget.chatId,
          peerName: widget.contactName,
        ),
      ),
    );
  }

  Widget _escrowStep(AzamanColors colors, String num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(num, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
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

  String _formatMessageTime(DateTime dt) {
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[dt.weekday - 1];
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  bool _shouldShowDateHeader(int index) {
    if (index == 0) return true;
    final current = _messages[index].timestamp;
    final previous = _messages[index - 1].timestamp;
    return current.day != previous.day || current.month != previous.month || current.year != previous.year;
  }
}

// Staggered Bouncing dots animation for typing status
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
          final offset = (value + 1.0) * 3.0; // Bounces up to 6px
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

// Waveform visualizer for recording voice notes
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

// iMessage Slanted Media Stack
class _SlantedMediaStack extends StatefulWidget {
  final List<String> imageUrls;
  const _SlantedMediaStack({required this.imageUrls});

  @override
  State<_SlantedMediaStack> createState() => _SlantedMediaStackState();
}

class _SlantedMediaStackState extends State<_SlantedMediaStack> {
  int _currentIndex = 0;

  void _cycleStack() {
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.imageUrls.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double maxW = 200.0;
    final double maxH = 170.0;

    return GestureDetector(
      onTap: _cycleStack,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: List.generate(widget.imageUrls.length, (idx) {
          // Calculate stack rendering depth
          final relativeIdx = (idx - _currentIndex) % widget.imageUrls.length;
          final depth = widget.imageUrls.length - 1 - relativeIdx;
          
          final double scale = 1.0 - (depth * 0.05);
          final double translationX = depth * 8.0;
          final double translationY = depth * 4.0;
          final double rotation = depth * 0.035; // Slant angle

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(translationX, translationY)
              ..rotateZ(rotation)
              ..scale(scale),
            child: Container(
              width: maxW, height: maxH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 4)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: widget.imageUrls[idx].startsWith('http')
                    ? Image.network(widget.imageUrls[idx], fit: BoxFit.cover)
                    : Image.asset(widget.imageUrls[idx], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey)),
              ),
            ),
          );
        }),
      ),
    );
  }
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
              color: textColor.withValues(alpha: 0.15),
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
                      color: textColor.withValues(alpha: 0.15),
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
                style: TextStyle(color: textColor.withValues(alpha: 0.65), fontSize: 9.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class PersonalChatMessage {
  final String id;
  final bool isMe;
  final String text;
  final String? mediaUrl;
  final String type; // 'text', 'image', 'crypto'
  String status; // 'sending', 'sent', 'delivered', 'read', 'failed'
  final DateTime createdAt;

  final double? cryptoAmount;
  final String? cryptoCurrency;
  final bool cryptoCompleted;

  PersonalChatMessage({
    required this.id,
    required this.isMe,
    required this.text,
    this.mediaUrl,
    this.type = 'text',
    this.status = 'sending',
    DateTime? createdAt,
    this.cryptoAmount,
    this.cryptoCurrency,
    this.cryptoCompleted = false,
  }) : createdAt = createdAt ?? DateTime.now();
}

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

class _PersonalChatInterfaceState extends ConsumerState<PersonalChatInterface> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  final List<PersonalChatMessage> _messages = [];
  bool _isLoading = true;
  String _nickname = '';

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  Future<void> _fetchMessages() async {
    setState(() => _isLoading = true);
    try {
      // Renamed local from `authProvider` to `auth` throughout this file
      // to avoid shadowing the top-level Riverpod `authProvider` symbol.
      final auth = ref.read(authProvider);
      final token = auth.user?.token;
      if (token == null) return;

      final response = await apiClient.get('/chat/personal/${widget.chatId}/messages');

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final List rawMessages = data['messages'] ?? [];
        setState(() {
          _messages.clear();
          for (final m in rawMessages) {
            final senderId = m['senderId']?.toString() ?? '';
            final currentUserId = auth.user?.id.toString() ?? '';
            _messages.add(PersonalChatMessage(
              id: m['id']?.toString() ?? '',
              isMe: senderId == currentUserId,
              text: m['text']?.toString() ?? '',
              mediaUrl: m['mediaUrl']?.toString(),
              type: m['type']?.toString() ?? 'text',
              status: 'read',
              createdAt: m['createdAt'] != null
                  ? DateTime.tryParse(m['createdAt'].toString()) ?? DateTime.now()
                  : DateTime.now(),
              cryptoAmount: (m['cryptoAmount'] as num?)?.toDouble(),
              cryptoCurrency: m['cryptoCurrency']?.toString(),
              cryptoCompleted: m['cryptoCompleted'] == true,
            ));
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
      final auth = ref.read(authProvider);
      final token = auth.user?.token;
      if (token == null) return;

      await apiClient.put('/chat/personal/${widget.chatId}/nickname', {'nickname': nickname});
    } catch (e) {
      debugPrint('save nickname error: $e');
    }
  }

  void _showNicknameDialog() {
    final colors = ref.read(themeProvider).colors;
    final controller = TextEditingController(text: _nickname);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Nickname',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter nickname for ${widget.contactName}',
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
              final nick = controller.text.trim();
              if (nick.isNotEmpty) {
                setState(() => _nickname = nick);
                _saveNickname(nick);
              }
              Navigator.pop(ctx);
            },
            child: Text('Save', style: TextStyle(color: colors.isDark ? Colors.black : Colors.white)),
          ),
        ],
      ),
    );
  }

  void _sendTextMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();

    final msg = PersonalChatMessage(
      id: 'tmp_${DateTime.now().microsecondsSinceEpoch}',
      isMe: true,
      text: text,
      status: 'sending',
    );
    setState(() => _messages.add(msg));
    _scrollToBottom();

    _persistMessage(msg);
  }

  Future<void> _persistMessage(PersonalChatMessage msg) async {
    try {
      final auth = ref.read(authProvider);
      final token = auth.user?.token;
      if (token == null) return;

      final body = <String, dynamic>{
        'text': msg.text,
        'type': msg.type,
      };
      if (msg.cryptoAmount != null) {
        body['cryptoAmount'] = msg.cryptoAmount;
        body['cryptoCurrency'] = msg.cryptoCurrency;
        body['cryptoCompleted'] = msg.cryptoCompleted;
      }

      final response = await apiClient.post(
        '/chat/personal/${widget.chatId}/messages',
        body,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            msg.status = 'sent';
            if (data['id'] != null) {
              // replace temp id with server id via index
              final idx = _messages.indexOf(msg);
              if (idx != -1) {
                _messages[idx] = PersonalChatMessage(
                  id: data['id'].toString(),
                  isMe: msg.isMe,
                  text: msg.text,
                  mediaUrl: msg.mediaUrl,
                  type: msg.type,
                  status: 'sent',
                  createdAt: msg.createdAt,
                  cryptoAmount: msg.cryptoAmount,
                  cryptoCurrency: msg.cryptoCurrency,
                  cryptoCompleted: msg.cryptoCompleted,
                );
              }
            }
          });
        }
      } else if (mounted) {
        setState(() => msg.status = 'failed');
      }
    } catch (e) {
      debugPrint('persist message error: $e');
      if (mounted) setState(() => msg.status = 'failed');
    }
  }

  void _showMoreActions() {
    final colors = ref.read(themeProvider).colors;
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('More Actions',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(HugeIconsSolid.bitcoin, color: colors.accent, size: 24),
              ),
              title: Text('Send Crypto',
                  style: TextStyle(
                      color: colors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Transfer directly in chat',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _handleSendCrypto();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(HugeIconsSolid.image01, color: colors.accent, size: 24),
              ),
              title: Text('Send Photo',
                  style: TextStyle(
                      color: colors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Share an image from your gallery',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSendCrypto() async {
    final colors = ref.read(themeProvider).colors;
    final amountController = TextEditingController();

    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        double? selected;
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: null,
                ),
                Text('Send Crypto',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                const SizedBox(height: 8),
                Text('Transfer AZM to $_displayName',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                const SizedBox(height: 20),
                Text('Amount (AZM)',
                    style: TextStyle(
                        color: colors.textPrimary.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(color: colors.textTertiary, fontSize: 24),
                    filled: true,
                    fillColor: colors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.accent, width: 2),
                    ),
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    setSheetState(() => selected = parsed);
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.divider),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text('Cancel',
                            style: TextStyle(color: colors.textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: selected != null && selected! > 0
                            ? () => Navigator.pop(ctx, selected)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: colors.isDark ? Colors.black : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Next',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        });
      },
    );

    if (amount == null || amount <= 0) return;

    final bool authenticated = await _authenticateBiometric();
    if (!authenticated || !mounted) return;

    _executeCryptoTransfer(amount);
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

  Future<void> _executeCryptoTransfer(double amount) async {
    if (!mounted) return;
    final colors = ref.read(themeProvider).colors;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Processing transfer...'),
      backgroundColor: colors.accent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 1),
    ));

    try {
      final auth = ref.read(authProvider);
      final token = auth.user?.token;
      if (token == null) return;

      final response = await apiClient.post(
        '/chat/personal/${widget.chatId}/transfer',
        {
          'amount': amount,
          'currency': 'AZM',
          'recipientAzamanId': widget.contactAzamanId,
        },
      );

      final bool completed = response.statusCode == 200 || response.statusCode == 201;

      if (mounted) {
        final cryptoMsg = PersonalChatMessage(
          id: 'crypto_${DateTime.now().microsecondsSinceEpoch}',
          isMe: true,
          text: 'Sent $amount AZM',
          type: 'crypto',
          status: completed ? 'sent' : 'failed',
          cryptoAmount: amount,
          cryptoCurrency: 'AZM',
          cryptoCompleted: completed,
        );
        setState(() => _messages.add(cryptoMsg));
        _scrollToBottom();
        _persistMessage(cryptoMsg);

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(completed
              ? '$amount AZM sent successfully!'
              : 'Transfer failed. Please try again.'),
          backgroundColor: completed ? colors.success : colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('transfer error: $e');
      if (mounted) {
        final cryptoMsg = PersonalChatMessage(
          id: 'crypto_${DateTime.now().microsecondsSinceEpoch}',
          isMe: true,
          text: 'Sent $amount AZM',
          type: 'crypto',
          status: 'failed',
          cryptoAmount: amount,
          cryptoCurrency: 'AZM',
          cryptoCompleted: false,
        );
        setState(() => _messages.add(cryptoMsg));
        _scrollToBottom();

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Transfer failed. Please try again.'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    if (diff.inDays < 1) return '$h:$m $p';
    return '${dt.month}/${dt.day} $h:$m $p';
  }

  Widget _statusTicks(String status, AzamanColors colors) {
    switch (status) {
      case 'sending':
        return Icon(HugeIconsSolid.clock01, size: 13, color: colors.textTertiary.withValues(alpha: 0.6));
      case 'failed':
        return Icon(HugeIconsSolid.alertCircle, size: 13, color: colors.danger);
      case 'read':
        return Icon(HugeIconsSolid.checkmarkCircle01, size: 13, color: colors.accent);
      case 'delivered':
        return Icon(HugeIconsSolid.checkmarkCircle01, size: 13, color: colors.textTertiary);
      default:
        return Icon(HugeIconsSolid.checkmarkCircle01, size: 13, color: colors.textTertiary);
    }
  }

  Widget _transactionBubble(PersonalChatMessage msg, AzamanColors colors) {
    final bool completed = msg.cryptoCompleted;
    final Color borderColor = completed ? colors.success : colors.danger;

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  HugeIconsSolid.bitcoin,
                  size: 20,
                  color: completed ? colors.success : colors.danger,
                ),
                const SizedBox(width: 8),
                Text(
                  'CRYPTO TRANSFER',
                  style: TextStyle(
                    color: completed ? colors.success : colors.danger,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  msg.cryptoAmount?.toStringAsFixed(4) ?? '0.00',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  msg.cryptoCurrency ?? 'AZM',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  completed ? HugeIconsSolid.checkmarkCircle01 : HugeIconsSolid.cancel01,
                  size: 16,
                  color: completed ? colors.success : colors.danger,
                ),
                const SizedBox(width: 6),
                Text(
                  completed ? 'Completed' : 'Failed',
                  style: TextStyle(
                    color: completed ? colors.success : colors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(msg.createdAt),
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _textBubble(PersonalChatMessage msg, AzamanColors colors) {
    final bool isMe = msg.isMe;
    final Color bubbleColor = isMe ? colors.accent : colors.card;
    final Color textColor = isMe
        ? (colors.isDark ? Colors.black : Colors.white)
        : colors.textPrimary;
    final Color metaColor = isMe
        ? (colors.isDark ? Colors.black54 : Colors.white70)
        : colors.textTertiary;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
          border: isMe ? null : Border.all(color: colors.divider),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (msg.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  msg.text,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg.createdAt),
                  style: TextStyle(color: metaColor, fontSize: 10),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _statusTicks(msg.status, colors),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: GestureDetector(
          onTap: _showNicknameDialog,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _displayName,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 6),
              Icon(HugeIconsSolid.pencilEdit01, size: 14, color: colors.textTertiary),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(HugeIconsSolid.informationCircle, color: colors.accent),
            onPressed: _showNicknameDialog,
            tooltip: 'Contact Info',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: colors.accent))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(HugeIconsSolid.bubbleChat,
                                size: 48, color: colors.textTertiary),
                            const SizedBox(height: 12),
                            Text('No messages yet',
                                style: TextStyle(color: colors.textSecondary)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final msg = _messages[i];
                          if (msg.type == 'crypto') {
                            return _transactionBubble(msg, colors);
                          }
                          return _textBubble(msg, colors);
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            color: colors.surface,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(HugeIconsSolid.addCircle,
                        color: colors.accent, size: 28),
                    tooltip: 'More actions',
                    onPressed: _showMoreActions,
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: colors.divider),
                      ),
                      child: TextField(
                        controller: _chatController,
                        style: TextStyle(color: colors.textPrimary),
                        onSubmitted: (_) => _sendTextMessage(),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(color: colors.textTertiary),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: colors.accent,
                    radius: 22,
                    child: IconButton(
                      icon: Icon(HugeIconsSolid.sent,
                          color: colors.isDark ? Colors.black : Colors.white,
                          size: 20),
                      onPressed: _sendTextMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

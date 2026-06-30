import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

import 'package:azaman/widgets/chat_plus_menu.dart';

class PersonalChatMessage {
  final String id;
  final bool isMe;
  final String text;
  final String? mediaUrl;
  final String type;
  String status;
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
  final FocusNode _inputFocus = FocusNode();

  final List<PersonalChatMessage> _messages = [];
  bool _isLoading = true;
  String _nickname = '';
  bool _inputHasText = false;

  @override
  void initState() {
    super.initState();
    _chatController.addListener(() {
      final has = _chatController.text.trim().isNotEmpty;
      if (has != _inputHasText) setState(() => _inputHasText = has);
    });
    _fetchMessages();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    setState(() => _isLoading = true);
    try {
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
                'Edit nickname',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Set a custom name for ${widget.contactName}',
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
                    hintText: 'Nickname',
                    hintStyle: TextStyle(
                      color: colors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
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
                    final nick = controller.text.trim();
                    if (nick.isNotEmpty) {
                      setState(() => _nickname = nick);
                      _saveNickname(nick);
                    }
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Save',
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
    );
  }

  void _sendTextMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    HapticFeedback.lightImpact();

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
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
            const SizedBox(height: 20),
            _buildActionRow(
              colors: colors,
              icon: Icons.currency_bitcoin,
              title: 'Send Crypto',
              subtitle: 'Transfer AZM directly',
              onTap: () {
                Navigator.pop(ctx);
                _handleSendCrypto();
              },
            ),
            const SizedBox(height: 4),
            _buildActionRow(
              colors: colors,
              icon: Icons.image_outlined,
              title: 'Send Photo',
              subtitle: 'Share from gallery',
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 4),
            _buildActionRow(
              colors: colors,
              icon: Icons.edit_outlined,
              title: 'Edit Nickname',
              subtitle: 'Change display name',
              onTap: () {
                Navigator.pop(ctx);
                _showNicknameDialog();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required AzamanColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.textPrimary, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward,
              color: colors.textTertiary,
              size: 16,
            ),
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        double? selected;
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.textTertiary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Send Crypto',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Transfer AZM to $_displayName',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Amount (AZM)',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.softSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: amountController,
                      autofocus: true,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        setSheetState(() => selected = parsed);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: colors.softSurface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: selected != null && selected! > 0
                              ? () => Navigator.pop(ctx, selected)
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: selected != null && selected! > 0
                                  ? colors.accent
                                  : colors.softSurface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Continue',
                              style: TextStyle(
                                color: selected != null && selected! > 0
                                    ? (colors.isDark ? Colors.black : Colors.white)
                                    : colors.textTertiary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
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
    final current = _messages[index].createdAt;
    final previous = _messages[index - 1].createdAt;
    return current.day != previous.day ||
           current.month != previous.month ||
           current.year != previous.year;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildHeader(colors),

          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: colors.accent,
                      strokeWidth: 2,
                    ),
                  )
                : _messages.isEmpty
                    ? _buildEmptyChat(colors)
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final msg = _messages[i];
                          return Column(
                            children: [
                              if (_shouldShowDateHeader(i))
                                _buildDateHeader(msg.createdAt, colors),
                              if (msg.type == 'crypto')
                                _transactionBubble(msg, colors)
                              else
                                _textBubble(msg, colors),
                            ],
                          );
                        },
                      ),
          ),

          _buildInputBar(colors),
        ],
      ),
    );
  }

  Widget _buildHeader(AzamanColors colors) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.divider.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 14, 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back,
                  color: colors.textPrimary,
                  size: 22,
                ),
              ),
            ),

            const SizedBox(width: 4),

            CircleAvatar(
              radius: 19,
              backgroundColor: colors.softSurface,
              child: Text(
                _displayName.isNotEmpty
                    ? _displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: colors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Online',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Ticket-type badge placeholder
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'TICKET',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            const SizedBox(width: 6),

            GestureDetector(
              onTap: () {},
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.softSurface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.info_outline,
                  color: colors.textSecondary,
                  size: 18,
                ),
              ),
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
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.softSurface,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _displayName.isNotEmpty ? _displayName[0].toUpperCase() : '?',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _displayName,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Send a message to start the conversation',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(DateTime date, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 0.5,
              color: colors.divider.withValues(alpha: 0.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              _formatDateHeader(date),
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 0.5,
              color: colors.divider.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(String status, AzamanColors colors) {
    switch (status) {
      case 'sending':
        return Icon(Icons.access_time, size: 12, color: colors.textTertiary.withValues(alpha: 0.5));
      case 'failed':
        return Icon(Icons.error_outline, size: 12, color: colors.danger);
      case 'read':
        return Icon(Icons.check_circle_outline, size: 12, color: colors.accent);
      default:
        return Icon(Icons.check_circle_outline, size: 12, color: colors.textTertiary.withValues(alpha: 0.5));
    }
  }

  Widget _transactionBubble(PersonalChatMessage msg, AzamanColors colors) {
    final bool completed = msg.cryptoCompleted;
    final statusColor = completed ? colors.success : colors.danger;

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: colors.softSurface,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.currency_bitcoin,
                  size: 20,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    completed ? 'Transfer complete' : 'Transfer failed',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  msg.cryptoAmount?.toStringAsFixed(2) ?? '0.00',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  msg.cryptoCurrency ?? 'AZM',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatMessageTime(msg.createdAt),
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textBubble(PersonalChatMessage msg, AzamanColors colors) {
    final bool isMe = msg.isMe;

    final Color bubbleColor = isMe
        ? colors.accent
        : colors.softSurface;

    final Color textColor = isMe
        ? (colors.isDark ? Colors.black : Colors.white)
        : colors.textPrimary;

    final Color metaColor = isMe
        ? (colors.isDark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.7))
        : colors.textTertiary;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
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
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (msg.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  msg.text,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatMessageTime(msg.createdAt),
                  style: TextStyle(
                    color: metaColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _statusIcon(msg.status, colors),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(AzamanColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(
            color: colors.divider.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ChatPlusMenu(
            onTransferTap: _handleSendCrypto,
            onEscrowTap: _showEscrowInstructions,
            onImageTap: _pickImage,
            onDocumentTap: _pickDocument,
            onStickerTap: _showStickerSheet,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: colors.softSurface,
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _chatController,
                focusNode: _inputFocus,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                onSubmitted: (_) => _sendTextMessage(),
                decoration: InputDecoration(
                  hintText: 'Message',
                  hintStyle: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          GestureDetector(
            onTap: _inputHasText ? _sendTextMessage : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: _inputHasText ? colors.accent : colors.softSurface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.send_outlined,
                color: _inputHasText
                    ? (colors.isDark ? Colors.black : Colors.white)
                    : colors.textTertiary,
                size: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEscrowInstructions() {
    final colors = ref.read(themeProvider).colors;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('How Escrow Works',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20, fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _escrowStep(colors, '1', 'Agree Terms', 'Both parties confirm the deal details in the ticket.'),
              _escrowStep(colors, '2', 'Buyer Funds Escrow', 'The buyer locks funds using the Initiate Escrow button. Funds are held securely.'),
              _escrowStep(colors, '3', 'Seller Delivers', 'The seller fulfils the agreed service or delivers the goods.'),
              _escrowStep(colors, '4', 'Automatic Release', 'Once the buyer confirms delivery, funds are released. Disputes trigger admin review.'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Initiate Escrow Now',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
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
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(num,
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(desc,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pickImage() {}
  void _pickDocument() {}
  void _showStickerSheet() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stickers coming soon')),
    );
  }
}

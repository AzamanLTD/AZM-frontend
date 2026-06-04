// =============================================================================
// DIRECT MESSAGE SCREEN — Azaman Phase 3.3
//
// Social chat interface with in-chat value transfers:
//   • Premium dark theme with glassmorphism
//   • Action button (+) next to message input
//   • Dark-themed bottom sheet for crypto transfers
//   • Number pad input with Send button
//   • Biometric authentication integration
//
// Architecture:
//   • Uses Riverpod for state management
//   • Bottom sheet with glassmorphism effects
//   • Real-time balance updates
//   • Transaction message bubbles
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'dart:ui';

class DirectMessageScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String contactId;
  final String contactName;
  final String contactAzamanId;

  const DirectMessageScreen({
    super.key,
    required this.chatId,
    required this.contactId,
    required this.contactName,
    required this.contactAzamanId,
  });

  @override
  ConsumerState<DirectMessageScreen> createState() => _DirectMessageScreenState();
}

class _DirectMessageScreenState extends ConsumerState<DirectMessageScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LocalAuthentication _localAuth = LocalAuthentication();



  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addWelcomeMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final params = {
        'chatId': widget.chatId,
        'contactId': widget.contactId,
        'contactName': widget.contactName,
      };
      ref.read(directChatProvider(params).notifier).addMessage(
            ChatMessage(
              id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
              senderId: 'system',
              text: 'Chat with ${widget.contactName} started. You can send messages or transfer crypto.',
              timestamp: DateTime.now(),
              type: MessageType.system,
              isMe: false,
            ),
          );
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.selectionClick();
    final params = {
      'chatId': widget.chatId,
      'contactId': widget.contactId,
      'contactName': widget.contactName,
    };
    ref.read(directChatProvider(params).notifier).addMessage(
          ChatMessage(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            senderId: 'me',
            text: text,

            timestamp: DateTime.now(),
            type: MessageType.text,
            isMe: true,
          ),
        );

    _messageController.clear();
    _scrollToBottom();
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

  void _showValueTransferSheet() {
    HapticFeedback.mediumImpact();
    final colors = ref.read(themeProvider).colors;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ValueTransferBottomSheet(
        contactName: widget.contactName,
        contactAzamanId: widget.contactAzamanId,
        onTransferConfirmed: (amount, currency) {
          _handleCryptoTransfer(amount, currency);
        },
      ),
    );
  }

  Future<void> _handleCryptoTransfer(double amount, String currency) async {
    // Authenticate with biometrics
    final authenticated = await _authenticateBiometric();
    if (!authenticated || !mounted) return;

    final colors = ref.read(themeProvider).colors;


    // Show processing
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Processing transfer...'),
        backgroundColor: colors.glow,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    // Simulate transfer (in production, this would call backend API)
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      final params = {
        'chatId': widget.chatId,
        'contactId': widget.contactId,
        'contactName': widget.contactName,
      };
      ref.read(directChatProvider(params).notifier).sendCryptoTransfer(amount, currency);
      
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully sent $amount $currency to ${widget.contactName}!'),
          backgroundColor: colors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      _scrollToBottom();
    }
  }

  Future<bool> _authenticateBiometric() async {
    final colors = ref.read(themeProvider).colors;
    try {
      final bool canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) {
        final bool deviceSupport = await _localAuth.isDeviceSupported();
        if (!deviceSupport) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Biometrics not available on this device'),

                backgroundColor: colors.danger,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return false;
        }
      }

      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate to send crypto to ${widget.contactName}',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!didAuthenticate && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Authentication failed'),
            backgroundColor: colors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      return didAuthenticate;
    } catch (e) {
      debugPrint('biometric auth error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Biometric authentication error'),
            backgroundColor: colors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);

    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final params = {
      'chatId': widget.chatId,
      'contactId': widget.contactId,
      'contactName': widget.contactName,
    };
    final chatState = ref.watch(directChatProvider(params));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: colors.glow.withOpacity(0.2),
              radius: 18,
              child: Text(
                widget.contactName.isNotEmpty ? widget.contactName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: colors.glow,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.contactName,

                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '@${widget.contactAzamanId}',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline_rounded, color: colors.glow),
            onPressed: () {
              // Show contact info
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyState(colors)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, i) {
                      final msg = chatState.messages[i];
                      return _buildMessageBubble(msg, colors);
                    },
                  ),
          ),

          // Message input with action button
          _buildInputField(colors),
        ],
      ),

    );
  }

  Widget _buildEmptyState(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 48, color: colors.textTertiary),
          const SizedBox(height: 12),
          Text(
            'Start a conversation',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Send a message or transfer crypto',
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, AzamanColors colors) {
    if (msg.type == MessageType.system) {
      return _buildSystemMessage(msg, colors);
    } else if (msg.type == MessageType.transaction) {
      return _buildTransactionBubble(msg, colors);
    } else {
      return _buildTextBubble(msg, colors);
    }
  }

  Widget _buildSystemMessage(ChatMessage msg, AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.card.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(Icons.info_outline_rounded, color: colors.accentSecondary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg.text,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionBubble(ChatMessage msg, AzamanColors colors) {
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: msg.isMe
                ? [colors.success.withOpacity(0.25), colors.success.withOpacity(0.15)]
                : [colors.card, colors.card.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: msg.isMe ? colors.success : colors.accentSecondary,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: msg.isMe ? colors.success.withOpacity(0.2) : colors.accentSecondary.withOpacity(0.15),
              blurRadius: 12,

              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: msg.isMe ? colors.success.withOpacity(0.2) : colors.accentSecondary.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.currency_bitcoin,
                    color: msg.isMe ? colors.success : colors.accentSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'CRYPTO TRANSFER',
                  style: TextStyle(
                    color: msg.isMe ? colors.success : colors.accentSecondary,
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
                  '${msg.amount?.toStringAsFixed(2) ?? '0.00'}',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  msg.currency ?? 'AZM',
                  style: TextStyle(
                    color: colors.textSecondary,

                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: colors.success, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Completed',
                      style: TextStyle(
                        color: colors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  _formatTime(msg.timestamp),
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

  Widget _buildTextBubble(ChatMessage msg, AzamanColors colors) {
    final isMe = msg.isMe;
    final bubbleColor = isMe ? colors.glow : colors.card;
    final textColor = isMe ? Colors.black : colors.textPrimary;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,

        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: isMe ? null : Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: isMe ? colors.glow.withOpacity(0.2) : Colors.black26,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(msg.timestamp),
              style: TextStyle(
                color: isMe ? Colors.black54 : colors.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(AzamanColors colors) {
    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.divider),
        ),
      ),
      child: Row(
        children: [
          // Action button (+) for value transfers
          GestureDetector(
            onTap: _showValueTransferSheet,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.accentSecondary, colors.accentSecondary.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.accentSecondary.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.black,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.divider),
              ),
              child: TextField(
                controller: _messageController,

                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.glow, colors.glow.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.glow.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.black,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// VALUE TRANSFER BOTTOM SHEET
// =============================================================================

class _ValueTransferBottomSheet extends ConsumerStatefulWidget {
  final String contactName;
  final String contactAzamanId;

  final Function(double amount, String currency) onTransferConfirmed;

  const _ValueTransferBottomSheet({
    required this.contactName,
    required this.contactAzamanId,
    required this.onTransferConfirmed,
  });

  @override
  ConsumerState<_ValueTransferBottomSheet> createState() => _ValueTransferBottomSheetState();
}

class _ValueTransferBottomSheetState extends ConsumerState<_ValueTransferBottomSheet> {
  String _amount = '';
  final String _currency = 'AZM';

  void _onNumberTap(String number) {
    HapticFeedback.selectionClick();
    setState(() {
      if (number == '.' && _amount.contains('.')) return;
      if (_amount.length >= 10) return;
      _amount += number;
    });
  }

  void _onBackspace() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_amount.isNotEmpty) {
        _amount = _amount.substring(0, _amount.length - 1);
      }
    });
  }

  void _onSend() {
    final amount = double.tryParse(_amount);
    if (amount == null || amount <= 0) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
    widget.onTransferConfirmed(amount, _currency);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    final amount = double.tryParse(_amount);
    final isValid = amount != null && amount > 0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors.surface.withOpacity(0.95),
                  colors.card.withOpacity(0.9),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: colors.glow.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Send Crypto',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,

                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'to ${widget.contactName}',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 30),

                // Amount display
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: colors.background.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colors.glow.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _amount.isEmpty ? '0' : _amount,
                        style: TextStyle(
                          color: colors.glow,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currency,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Number pad

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      _buildNumberRow(['1', '2', '3'], colors),
                      const SizedBox(height: 12),
                      _buildNumberRow(['4', '5', '6'], colors),
                      const SizedBox(height: 12),
                      _buildNumberRow(['7', '8', '9'], colors),
                      const SizedBox(height: 12),
                      _buildNumberRow(['.', '0', '⌫'], colors),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Send button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isValid ? _onSend : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isValid ? colors.glow : colors.card,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: isValid ? 8 : 0,
                        shadowColor: colors.glow.withOpacity(0.5),
                      ),
                      child: Text(
                        'Send ${isValid ? "${amount!.toStringAsFixed(2)} $_currency" : ""}',
                        style: TextStyle(
                          color: isValid ? Colors.black : colors.textTertiary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberRow(List<String> numbers, AzamanColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: numbers.map((num) => _buildNumberButton(num, colors)).toList(),
    );
  }

  Widget _buildNumberButton(String text, AzamanColors colors) {
    final isBackspace = text == '⌫';
    final isDot = text == '.';

    return GestureDetector(
      onTap: () {
        if (isBackspace) {
          _onBackspace();
        } else {
          _onNumberTap(text);
        }
      },
      child: Container(
        width: 80,
        height: 64,
        decoration: BoxDecoration(
          color: colors.card.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.divider.withOpacity(0.3),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            color: isBackspace ? colors.danger : colors.textPrimary,
            fontSize: isDot ? 32 : 24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

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

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' as intl;

import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/models/chat_theme_model.dart';
import 'package:azaman/widgets/chat_plus_menu.dart';
import 'package:azaman/widgets/sticker_sheet.dart';


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
  final ImagePicker _imagePicker = ImagePicker();

  ChatMessage? _replyToMessage;
  bool _partnerIsTyping = false;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
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
            replyToId: _replyToMessage?.id,
            replyToText: _replyToMessage?.text,
            replyToSenderName: _replyToMessage?.isMe == true ? 'You' : widget.contactName,
          ),
        );

    _messageController.clear();
    setState(() => _replyToMessage = null);
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

  void _showWallpaperPicker() {
    final chatTheme = ref.read(chatThemeProvider(widget.chatId));
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ref.read(themeProvider).colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Chat Wallpaper',
              style: TextStyle(
                color: ref.read(themeProvider).colors.textPrimary,
                fontSize: 16, fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: 7,
              itemBuilder: (ctx, i) {
                final wallpapers = ChatWallpaper.values;
                final wp = wallpapers[i];
                final isSelected = chatTheme.wallpaper == wp;
                return GestureDetector(
                  onTap: () {
                    ref.read(chatThemeProvider(widget.chatId).notifier).setWallpaper(wp);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? ref.read(themeProvider).colors.accent : Colors.transparent,
                        width: 2,
                      ),
                      image: wp == ChatWallpaper.none ? null : DecorationImage(
                        image: AssetImage('assets/chat_wallpapers/wp_${wp.name}.jpg'),
                        fit: BoxFit.cover,
                      ),
                      color: wp == ChatWallpaper.none ? ref.read(themeProvider).colors.card : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final params = {
      'chatId': widget.chatId,
      'contactId': widget.contactId,
      'contactName': widget.contactName,
    };
    ref.read(directChatProvider(params).notifier).addMessage(
      ChatMessage(
        id: 'img_${DateTime.now().millisecondsSinceEpoch}',
        senderId: 'me',
        text: '',
        timestamp: DateTime.now(),
        type: MessageType.image,
        isMe: true,
        mediaUrl: file.path,
        mediaType: 'image',
      ),
    );
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final params = {
      'chatId': widget.chatId,
      'contactId': widget.contactId,
      'contactName': widget.contactName,
    };
    ref.read(directChatProvider(params).notifier).addMessage(
      ChatMessage(
        id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
        senderId: 'me',
        text: result.files.single.name,
        timestamp: DateTime.now(),
        type: MessageType.document,
        isMe: true,
        mediaUrl: path,
        mediaType: 'document',
      ),
    );
  }

  void _showStickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StickerSheet(
        onStickerSelected: (path, isAnimated) {
          _sendSticker(path, isAnimated);
        },
      ),
    );
  }

  void _sendSticker(String assetPath, bool isAnimated) {
    final params = {
      'chatId': widget.chatId,
      'contactId': widget.contactId,
      'contactName': widget.contactName,
    };
    ref.read(directChatProvider(params).notifier).addMessage(
      ChatMessage(
        id: 'sticker_${DateTime.now().millisecondsSinceEpoch}',
        senderId: 'me',
        text: '',
        timestamp: DateTime.now(),
        type: MessageType.sticker,
        isMe: true,
        stickerAssetPath: assetPath,
        isAnimatedSticker: isAnimated,
      ),
    );
    _scrollToBottom();
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
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () {},
          child: Row(
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
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _partnerIsTyping
                              ? colors.success
                              : colors.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _partnerIsTyping ? 'Online' : 'Offline',
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
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.call_outlined, color: colors.glow),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.palette_outlined, color: colors.glow),
            onPressed: () => _showWallpaperPicker(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Wallpaper background
          Consumer(
            builder: (ctx, ref, _) {
              final theme = ref.watch(chatThemeProvider(widget.chatId));
              if (theme.wallpaper != ChatWallpaper.none) {
                return Positioned.fill(
                  child: Image.asset(
                    theme.wallpaperAsset,
                    fit: BoxFit.cover,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Column(
            children: [
              // Messages list
              Expanded(
                child: chatState.messages.isEmpty
                    ? _buildEmptyState(colors)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: chatState.messages.length + (_partnerIsTyping ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (_partnerIsTyping && i == chatState.messages.length) {
                            return _buildTypingIndicator(colors);
                          }
                          final msg = chatState.messages[i];
                          final prevMsg = i > 0 ? chatState.messages[i - 1] : null;
                          return _buildMessageBubble(msg, prevMsg, colors);
                        },
                      ),
              ),

              // Reply banner
              if (_replyToMessage != null)
                _buildReplyBanner(colors),

              // Message input with action button
              _buildInputField(colors),
            ],
          ),
        ],
      ),

    );
  }

  Widget _buildEmptyState(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: colors.textTertiary),
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

  Widget _buildReplyBanner(AzamanColors colors) {
    final msg = _replyToMessage!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            color: colors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.isMe ? 'You' : widget.contactName,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  msg.text.length > 200
                      ? '${msg.text.substring(0, 200)}...'
                      : msg.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.cancel_outlined, color: colors.textTertiary, size: 16),
            onPressed: () => setState(() => _replyToMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(AzamanColors colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: Duration(milliseconds: 400 + i * 200),
              builder: (_, val, __) {
                return Transform.scale(
                  scale: val,
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: colors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, ChatMessage? prevMsg, AzamanColors colors) {
    if (_shouldShowDateChip(msg, prevMsg)) {
      return Column(
        children: [
          _buildDateChip(msg.timestamp, colors),
          const SizedBox(height: 8),
          _buildBubbleForType(msg, colors),
        ],
      );
    }
    return _buildBubbleForType(msg, colors);
  }

  bool _shouldShowDateChip(ChatMessage msg, ChatMessage? prevMsg) {
    if (prevMsg == null) return true;
    final current = DateTime(msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);
    final previous = DateTime(prevMsg.timestamp.year, prevMsg.timestamp.month, prevMsg.timestamp.day);
    return current != previous;
  }

  Widget _buildDateChip(DateTime date, AzamanColors colors) {
    String label;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(date.year, date.month, date.day);
    final diff = today.difference(msgDate).inDays;
    if (diff == 0) {
      label = 'Today';
    } else if (diff == 1) {
      label = 'Yesterday';
    } else {
      label = intl.DateFormat('EEE d MMM').format(date);
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleForType(ChatMessage msg, AzamanColors colors) {
    switch (msg.type) {
      case MessageType.system:
        return _buildSystemMessage(msg, colors);
      case MessageType.transaction:
        return _buildTransactionBubble(msg, colors);
      case MessageType.image:
        return _buildMediaBubble(msg, colors);
      case MessageType.document:
        return _buildDocumentBubble(msg, colors);
      case MessageType.sticker:
        return _buildStickerBubble(msg, colors);
      default:
        return _buildTextBubble(msg, colors);
    }
  }

  Widget _buildMediaBubble(ChatMessage msg, AzamanColors colors) {
    return GestureDetector(
      onLongPress: () => setState(() => _replyToMessage = msg),
      child: Align(
        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          width: 220,
          constraints: const BoxConstraints(maxHeight: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: colors.card,
          ),
          child: msg.mediaUrl != null && msg.mediaUrl!.startsWith('http')
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(msg.mediaUrl!, fit: BoxFit.cover),
                )
              : Icon(Icons.image_outlined, color: colors.textTertiary, size: 48),
        ),
      ),
    );
  }

  Widget _buildDocumentBubble(ChatMessage msg, AzamanColors colors) {
    return GestureDetector(
      onLongPress: () => setState(() => _replyToMessage = msg),
      child: Align(
        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.6,
          ),
          decoration: BoxDecoration(
            color: msg.isMe ? colors.glow : colors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined, color: colors.accent, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  msg.text.isNotEmpty ? msg.text : 'Document',
                  style: TextStyle(color: colors.textPrimary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickerBubble(ChatMessage msg, AzamanColors colors) {
    return GestureDetector(
      onLongPress: () => setState(() => _replyToMessage = msg),
      child: Align(
        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: msg.stickerAssetPath != null
              ? Image.asset(msg.stickerAssetPath!, width: 120, height: 120)
              : null,
        ),
      ),
    );
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
          Icon(Icons.info_outline, color: colors.accentSecondary, size: 16),
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
    final label = msg.isMe ? 'Sent' : 'Received';
    final contact = msg.isMe ? widget.contactName : widget.contactName;
    return GestureDetector(
      onTap: () => _showTransactionDetails(msg),
      child: Align(
        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          width: 280,
          height: 100,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.glow.withOpacity(0.85),
                colors.accent.withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [Colors.white.withOpacity(0.3), Colors.transparent],
                stops: const [0.0, 0.1],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(bounds),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.compare_arrows, color: Colors.white, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${msg.amount?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          msg.currency ?? 'USDC',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          '${msg.isMe ? "To" : "From"}: $contact',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 10,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Confirmed',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showTransactionDetails(ChatMessage msg) {
    final colors = ref.read(themeProvider).colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Transaction Details',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18, fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _detailRow('Reference', msg.id.length > 12 ? 'REF: ${msg.id.substring(0, 12)}' : msg.id, colors),
            _detailRow('Timestamp', _formatTime(msg.timestamp), colors),
            _detailRow('Amount', '${msg.amount?.toStringAsFixed(2) ?? '0.00'} ${msg.currency ?? 'USDC'}', colors),
            _detailRow('Status', 'Confirmed', colors),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Share.share(
                    'Azaman Transaction\n'
                    'Amount: ${msg.amount?.toStringAsFixed(2) ?? '0.00'} ${msg.currency ?? 'USDC'}\n'
                    'Status: Confirmed\n'
                    'Reference: ${msg.id}\n'
                    'Date: ${msg.timestamp}',
                  );
                },
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Share Receipt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildTextBubble(ChatMessage msg, AzamanColors colors) {
    final isMe = msg.isMe;
    final bubbleColor = isMe ? colors.glow : colors.card;
    final textColor = isMe ? Colors.black : colors.textPrimary;

    return GestureDetector(
      onLongPress: () => setState(() => _replyToMessage = msg),
      child: Align(
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
              if (msg.replyToId != null)
                _buildQuotedMessage(msg, colors),
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
      ),
    );
  }

  Widget _buildQuotedMessage(ChatMessage msg, AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: colors.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            msg.replyToSenderName ?? 'Unknown',
            style: TextStyle(
              color: colors.accent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            msg.replyToText ?? '',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
          // Chat Plus Menu
          ChatPlusMenu(
            onTransferTap: _showValueTransferSheet,
            onImageTap: _pickImage,
            onDocumentTap: _pickDocument,
            onStickerTap: _showStickerSheet,
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
                Icons.send_outlined,
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

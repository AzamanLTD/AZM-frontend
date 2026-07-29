import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/config.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/chat_plus_menu.dart';


class ChatInterface extends ConsumerStatefulWidget {
  final IO.Socket socket;
  final String tradeId;
  final String myRole; // 'user' (Buyer), 'vendor' (Seller), or 'admin'
  final List<Map<String, dynamic>> messages;
  final bool isTyping;
  // text, mediaUrl (already uploaded absolute URL or null)
  final Function(String text, String? mediaUrl) onSendMessage;
  // Optional callback for the time extension action in the + sheet
  final VoidCallback? onTimeExtension;

  const ChatInterface({
    super.key,
    required this.socket,
    required this.tradeId,
    required this.myRole,
    required this.messages,
    required this.isTyping,
    required this.onSendMessage,
    this.onTimeExtension,
  });

  @override
  ConsumerState<ChatInterface> createState() => _ChatInterfaceState();
}

class _ChatInterfaceState extends ConsumerState<ChatInterface> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    widget.socket.emit('mark_messages_read', {
      'tradeId': widget.tradeId,
      'readerId': widget.myRole,
    });
  }

  @override
  void didUpdateWidget(ChatInterface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length > oldWidget.messages.length) {
      _scrollToBottom();
      widget.socket.emit('mark_messages_read', {
        'tradeId': widget.tradeId,
        'readerId': widget.myRole,
      });
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

  // --- Upload helper: multipart POST to /api/chat/upload-media ---
  // Uses field name 'file'; backend accepts any field name.
  Future<String?> _uploadImage(String filePath) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/chat/upload-media');
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', filePath));

      final response = await apiClient.multipart('/chat/upload-media', req);
      final body = response.body;
      debugPrint('Chat upload response (${response.statusCode}): $body');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final RegExp re = RegExp(r'"(mediaUrl|url|path)"\s*:\s*"([^"]+)"');
        final match = re.firstMatch(body);
        if (match != null) return match.group(2);
      }
    } catch (e) {
      debugPrint('Chat upload error: $e');
    }
    return null;
  }

  Future<void> _handlePick(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 70);
    if (image == null) return;
    setState(() => _isUploading = true);
    final uploadedUrl = await _uploadImage(image.path);
    if (!mounted) return;
    setState(() => _isUploading = false);

    if (uploadedUrl != null) {
      widget.onSendMessage("", uploadedUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Upload failed. Try again.")),
      );
    }
  }

  void _handleSend() {
    if (_chatController.text.trim().isEmpty) return;
    widget.onSendMessage(_chatController.text.trim(), null);
    _chatController.clear();
    final userId = ref.read(authProvider).user?.id ?? '0';
    widget.socket.emit('typing_trade', {
      'tradeId': widget.tradeId,
      'userId': userId,
      'isTyping': false,
    });
  }

  // --- Format time as "10:42 AM" from ISO timestamp or fallback string ---
  String _formatTime(dynamic raw) {
    if (raw == null) return '';
    try {
      if (raw is String) {
        if (raw.contains('T') || raw.contains('-')) {
          final dt = DateTime.tryParse(raw)?.toLocal();
          if (dt != null) {
            final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
            final m = dt.minute.toString().padLeft(2, '0');
            final p = dt.hour >= 12 ? 'PM' : 'AM';
            return '$h:$m $p';
          }
        }
        return raw; // already formatted like "10:42 AM"
      }
    } catch (_) {}
    return '';
  }

  // --- Render 3-state ticks ---
  Widget _statusTicks(String? status, AzamanColors colors) {
    if (status == 'sending') {
      return Icon(Icons.access_time, size: 13, color: colors.textTertiary.withValues(alpha: 0.6));
    }
    if (status == 'failed') {
      return Icon(Icons.error_outline, size: 13, color: colors.danger);
    }
    if (status == 'read') {
      return Icon(Icons.check_circle_outline, size: 13, color: colors.accent);
    }
    if (status == 'delivered') {
      return Icon(Icons.check_circle_outline, size: 13, color: colors.textTertiary);
    }
    // sent or anything else
    return Icon(Icons.check_circle_outline, size: 13, color: colors.textTertiary);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Column(
      children: [
        // 1. MESSAGES LIST
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            // Telegram uses a fast, lightly-bouncing scroll with momentum.
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            // Keyboard-dismiss on drag (Telegram behavior)
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: widget.messages.length,
            itemBuilder: (context, i) {
              final msg = widget.messages[i];
              final String senderType = msg['sender'] ?? '';
              final bool isMe = senderType == widget.myRole;
              final bool isAdmin = senderType == 'admin';
              final bool isSystem = senderType == 'system';

              final String msgType = msg['type'] ?? 'text';
              final bool isMilestone = msgType == 'milestone_warning' || (textContainsMilestone(msg['text']?.toString() ?? ''));
              final bool isAdminIntervention = msgType == 'ADMIN_INTERVENTION';
              final bool isSystemUrgency = msgType == 'SYSTEM_URGENCY';
              final bool isOfflineVendor = msgType == 'OFFLINE_VENDOR';

              // Time extension cards — JSON-encoded content
              final rawText = msg['text']?.toString() ?? msg['content']?.toString() ?? '';
              if (rawText.contains('TIME_EXTENSION_REQUEST') || rawText.contains('TIME_EXTENSION_GRANTED')) {
                return _timeExtensionCard(msg, isMe, colors);
              }

              if (isAdminIntervention) return _adminInterventionBubble(msg, colors);
              if (isSystemUrgency) return _systemUrgencyBubble(msg, colors);
              if (isOfflineVendor) return _offlineVendorBanner(msg, colors);
              if (isAdmin) return _adminBanner(msg, colors);
              if (isSystem) return _systemBanner(msg, colors);
              if (isMilestone) return _milestoneBubble(msg, colors);

              return _chatBubble(msg, isMe, colors);
            },
          ),
        ),

        // 2. TYPING INDICATOR
        if (widget.isTyping)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 10),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.card,
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
                            width: 6, height: 6,
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
            ]),
          ),

        // 3. UPLOAD INDICATOR
        if (_isUploading)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 10),
            child: Row(children: [
              SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: colors.success)),
              const SizedBox(width: 10),
              Text("Uploading image...", style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            ]),
          ),

        // 4. INPUT BAR — Premium Fintech Chat Input (Phase Q5)
        _PremiumChatInput(
          chatController: _chatController,
          colors: colors,
          isUploading: _isUploading,
          myRole: widget.myRole,
          onSend: _handleSend,
          onPickGallery: () => _handlePick(ImageSource.gallery),
          onPickCamera: () => _handlePick(ImageSource.camera),
          onTimeExtension: widget.onTimeExtension,
          onChanged: (text) {
            final userId = ref.read(authProvider).user?.id ?? '0';
            widget.socket.emit('typing_trade', {
              'tradeId': widget.tradeId,
              'userId': userId,
              'isTyping': text.isNotEmpty,
            });
          },
        ),
      ],
    );
  }

  // --- MILESTONE WARNING DETECTION ---
  bool textContainsMilestone(String text) {
    final lower = text.toLowerCase();
    return lower.contains('1/3') || lower.contains('2/3') || lower.contains('3/3') ||
        lower.contains('milestone') || lower.contains('time warning');
  }

  int _extractMilestonePart(String text) {
    if (text.contains('1/3')) return 1;
    if (text.contains('2/3')) return 2;
    if (text.contains('3/3')) return 3;
    return 0;
  }

  // --- TIME EXTENSION CARD (inline message bubble) ---
  Widget _timeExtensionCard(Map<String, dynamic> msg, bool isMe, AzamanColors colors) {
    final raw = msg['text']?.toString() ?? msg['content']?.toString() ?? '';
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (data == null) return const SizedBox.shrink();

    final type = data['type']?.toString() ?? '';
    final isRequest = type == 'TIME_EXTENSION_REQUEST';
    final isGranted = type == 'TIME_EXTENSION_GRANTED';
    // BUGFIX (2026-05-31): track the request lifecycle so the buttons
    // disappear after the vendor grants/declines and both parties see
    // a final status. The BE now mutates the original request message's
    // `status` field via `message_updated` socket events; we simply
    // mirror that here.
    final status = (data['status']?.toString() ?? 'PENDING').toUpperCase();
    final addedMinutes = (data['addedMinutes'] as num?)?.toInt() ?? 0;
    final timeStr = _formatTime(msg['time'] ?? msg['createdAt']);
    final isVendor = widget.myRole == 'vendor';
    final messageId = msg['id'];

    Color accentColor;
    IconData icon;
    String title;
    String subtitle;

    if (isGranted) {
      accentColor = const Color(0xFF02C076);
      icon = Icons.check_circle_outline;
      title = 'Time Extended';
      subtitle = '+$addedMinutes minutes added to the timer';
    } else if (isRequest && status == 'APPROVED') {
      accentColor = const Color(0xFF02C076);
      icon = Icons.check_circle_outline;
      title = isVendor ? 'Fulfilled' : 'Request Approved';
      subtitle = '+$addedMinutes minutes granted';
    } else if (isRequest && status == 'DECLINED') {
      accentColor = const Color(0xFFEF4444);
      icon = Icons.cancel_outlined;
      title = isVendor ? 'Cancelled' : 'Request Declined';
      subtitle = isVendor
          ? 'You declined this request'
          : 'Vendor declined your request for more time';
    } else {
      // PENDING request
      accentColor = const Color(0xFFFFB800);
      icon = Icons.access_time;
      title = isVendor ? 'Time Extension Requested' : 'Awaiting Vendor Response';
      subtitle = '+$addedMinutes minutes requested';
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMe ? 14 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 14),
          ),
          border: Border.all(color: accentColor.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            // Buttons only render for the VENDOR while the request is still PENDING.
            if (isRequest && status == 'PENDING' && isVendor && messageId != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _declineTimeRequest(messageId),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.divider),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Decline', style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _approveTimeRequest(addedMinutes, messageId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Grant +$addedMinutes', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(color: colors.textTertiary, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveTimeRequest(int minutes, dynamic requestMessageId) async {
    // Optimistically flip this request's status to APPROVED so the
    // buttons disappear immediately on this device. The BE will also
    // emit `message_updated` for cross-device parity, but the local
    // flip prevents the duplicate-tap window between the API call and
    // the socket round-trip.
    final originalContent = _flipRequestStatusLocally(requestMessageId, 'APPROVED');
    try {
      final response = await apiClient.post('/trades/extend', {
        'tradeId': widget.tradeId,
        'addedMinutes': minutes,
        'isRequest': false,
        'requestMessageId': requestMessageId,
      });
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ Granted +$minutes min'), backgroundColor: const Color(0xFF02C076)),
        );
      } else if (response.statusCode == 409) {
        // Already responded — keep optimistic state, that's fine.
      } else {
        // Roll back optimistic flip on hard failure.
        if (originalContent != null) {
          _restoreRequestContent(requestMessageId, originalContent);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${response.body}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (originalContent != null) {
        _restoreRequestContent(requestMessageId, originalContent);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _declineTimeRequest(dynamic requestMessageId) async {
    final originalContent = _flipRequestStatusLocally(requestMessageId, 'DECLINED');
    try {
      final response = await apiClient.post('/trades/extend/respond', {
        'tradeId': widget.tradeId,
        'requestMessageId': requestMessageId,
        'action': 'decline',
      });
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request declined'), backgroundColor: Color(0xFFEF4444)),
        );
      } else if (response.statusCode == 409) {
        // Already responded — keep optimistic state.
      } else {
        if (originalContent != null) {
          _restoreRequestContent(requestMessageId, originalContent);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${response.body}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (originalContent != null) {
        _restoreRequestContent(requestMessageId, originalContent);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Mutate the message in `widget.messages` so the rebuild renders the
  // resolved card. Returns the previous content so callers can roll back.
  String? _flipRequestStatusLocally(dynamic messageId, String newStatus) {
    if (messageId == null) return null;
    for (final m in widget.messages) {
      if (m['id'] == messageId || m['id']?.toString() == messageId.toString()) {
        final raw = m['text']?.toString() ?? m['content']?.toString() ?? '';
        try {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          parsed['status'] = newStatus;
          final newRaw = jsonEncode(parsed);
          setState(() {
            m['text'] = newRaw;
            m['content'] = newRaw;
          });
          return raw;
        } catch (_) {}
      }
    }
    return null;
  }

  void _restoreRequestContent(dynamic messageId, String original) {
    for (final m in widget.messages) {
      if (m['id'] == messageId || m['id']?.toString() == messageId.toString()) {
        setState(() {
          m['text'] = original;
          m['content'] = original;
        });
        return;
      }
    }
  }

  // --- MILESTONE WARNING BUBBLE ---
  Widget _milestoneBubble(Map<String, dynamic> msg, AzamanColors colors) {
    final String text = (msg['text'] ?? '').toString();
    final int part = _extractMilestonePart(text);
    final String timeStr = _formatTime(msg['time'] ?? msg['createdAt']);

    final Color baseColor = part == 3 ? colors.danger : colors.warning;
    final Color bgColor = baseColor.withValues(alpha: 0.15);
    final Color borderColor = baseColor.withValues(alpha: 0.7);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                part == 3 ? Icons.error_outline : Icons.alarm,
                color: baseColor,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                part > 0 ? "MILESTONE $part/3" : "TIME WARNING",
                style: TextStyle(
                  color: baseColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timeStr,
            style: TextStyle(color: baseColor.withValues(alpha: 0.6), fontSize: 10),
          ),
        ],
      ),
    );
  }

  // --- SYSTEM URGENCY BUBBLE (critical system warnings) ---
  Widget _systemUrgencyBubble(Map<String, dynamic> msg, AzamanColors colors) {
    final String text = (msg['text'] ?? '').toString();
    final String timeStr = _formatTime(msg['time'] ?? msg['createdAt']);
    final int urgency = (msg['urgency'] as num?)?.toInt() ?? 1;
    final Color baseColor = urgency >= 3 ? colors.danger : colors.warning;
    final double glowOpacity = urgency >= 3 ? 0.4 : 0.2;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: baseColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: glowOpacity),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                urgency >= 3 ? Icons.error_outline : Icons.error_outline,
                color: baseColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                urgency >= 3 ? 'SYSTEM URGENCY' : 'SYSTEM NOTICE',
                style: TextStyle(
                  color: baseColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: baseColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'LVL $urgency',
                  style: TextStyle(color: baseColor, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            timeStr,
            style: TextStyle(color: baseColor.withValues(alpha: 0.6), fontSize: 10),
          ),
        ],
      ),
    );
  }

  // --- OFFLINE VENDOR WARNING ---
  Widget _offlineVendorBanner(Map<String, dynamic> msg, AzamanColors colors) {
    final String text = (msg['text'] ?? 'Vendor appears to be offline').toString();
    final String timeStr = _formatTime(msg['time'] ?? msg['createdAt']);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.warning.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi, color: colors.warning, size: 18),
              const SizedBox(width: 8),
              Text(
                'VENDOR OFFLINE',
                style: TextStyle(
                  color: colors.warning,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timeStr,
            style: TextStyle(color: colors.warning.withValues(alpha: 0.6), fontSize: 10),
          ),
        ],
      ),
    );
  }

  // --- ADMIN INTERVENTION BUBBLE ---
  Widget _adminInterventionBubble(Map<String, dynamic> msg, AzamanColors colors) {
    final String text = (msg['text'] ?? '').toString();
    final String timeStr = _formatTime(msg['time'] ?? msg['createdAt']);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 14, color: colors.isDark ? Colors.black : Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      'ADMIN',
                      style: TextStyle(
                        color: colors.isDark ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (msg['adminName'] != null)
                Text(
                  msg['adminName'].toString(),
                  style: TextStyle(color: colors.textTertiary, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.gavel, size: 14, color: colors.accent),
              const SizedBox(width: 4),
              Text(
                'Admin Intervention',
                style: TextStyle(color: colors.accent, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                timeStr,
                style: TextStyle(color: colors.textTertiary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- ADMIN SYSTEM BANNER ---
  Widget _adminBanner(Map<String, dynamic> msg, AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.danger, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.error_outline, color: colors.danger, size: 16),
            const SizedBox(width: 5),
            Text("SYSTEM ADMIN",
                style: TextStyle(color: colors.danger, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          Text(
            msg['text'] ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(_formatTime(msg['time'] ?? msg['createdAt']),
              style: TextStyle(color: colors.danger.withValues(alpha: 0.6), fontSize: 10)),
        ],
      ),
    );
  }

  // --- SYSTEM / STATE-CHANGE BANNER ---
  Widget _systemBanner(Map<String, dynamic> msg, AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
      ),
      child: Text(
        msg['text'] ?? '',
        textAlign: TextAlign.center,
        style: TextStyle(color: colors.accent, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  // --- STANDARD CHAT BUBBLE ---
  Widget _chatBubble(Map<String, dynamic> msg, bool isMe, AzamanColors colors) {
    final String? mediaUrl = (msg['mediaUrl'] ?? msg['imagePath'])?.toString();
    final bool hasMedia = mediaUrl != null && mediaUrl.isNotEmpty;
    final String text = (msg['text'] ?? '').toString();
    final String timeStr = _formatTime(msg['time'] ?? msg['createdAt']);
    final String? senderName = msg['senderName']?.toString();

    final Color bubbleColor = isMe ? colors.accent : colors.card;
    final Color textColor = isMe ? (colors.isDark ? Colors.black : Colors.white) : colors.textPrimary;
    final Color metaColor = isMe ? (colors.isDark ? Colors.black54 : Colors.white70) : colors.textTertiary;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
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
            if (hasMedia)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (senderName != null && senderName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(Icons.person_outline, size: 12, color: isMe ? metaColor : colors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Sender Account Name: $senderName',
                              style: TextStyle(
                                color: isMe ? metaColor : colors.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        mediaUrl.startsWith('http') ? mediaUrl : '${AppConfig.baseUrl}$mediaUrl',
                        height: 180, width: 200, fit: BoxFit.cover,
                        loadingBuilder: (c, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            height: 180, width: 200, color: colors.background,
                            child: Center(child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2)),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          if (File(mediaUrl).existsSync()) {
                            return Image.file(File(mediaUrl), height: 180, width: 200, fit: BoxFit.cover);
                          }
                          return Container(
                            height: 180, width: 200, color: colors.background,
                            child: Icon(Icons.image_outlined, color: colors.textTertiary, size: 36),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  text,
                  style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(timeStr, style: TextStyle(color: metaColor, fontSize: 10)),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _statusTicks(msg['status']?.toString(), colors),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PREMIUM CHAT INPUT — Fintech-Grade Glassmorphism Input Bar (Phase Q5)
//
// Features:
//   - Frosted glass container with subtle gradient border
//   - Floating rounded input with proper padding and focus glow
//   - Circular accent send button with subtle scale animation
//   - Attachment row: gallery + camera with gentle opacity transitions
//   - Proper safe-area inset handling for all device sizes
// =============================================================================
class _PremiumChatInput extends StatefulWidget {
  final TextEditingController chatController;
  final AzamanColors colors;
  final bool isUploading;
  final String myRole;
  final VoidCallback onSend;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback? onTimeExtension;
  final ValueChanged<String> onChanged;

  const _PremiumChatInput({
    required this.chatController,
    required this.colors,
    required this.isUploading,
    required this.myRole,
    required this.onSend,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onChanged,
    this.onTimeExtension,
  });

  @override
  State<_PremiumChatInput> createState() => _PremiumChatInputState();
}

class _PremiumChatInputState extends State<_PremiumChatInput> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.chatController.addListener(_onTextChange);
  }

  @override
  void dispose() {
    widget.chatController.removeListener(_onTextChange);
    super.dispose();
  }

  void _onTextChange() {
    final hasText = widget.chatController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _showAttachmentSheet() {
    final c = widget.colors;
    final isVendor = widget.myRole == 'vendor';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SheetAction(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  color: c.accent,
                  colors: c,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onPickCamera();
                  },
                ),
                _SheetAction(
                  icon: Icons.image_outlined,
                  label: 'Gallery',
                  color: const Color(0xFF02C076),
                  colors: c,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onPickGallery();
                  },
                ),
                if (widget.onTimeExtension != null)
                  _SheetAction(
                    icon: Icons.access_time,
                    label: isVendor ? 'Extend Time' : 'Request Time',
                    color: const Color(0xFFFFB800),
                    colors: c,
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onTimeExtension!();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final isAdmin = widget.myRole == 'admin';
    final accentColor = isAdmin ? c.danger : c.accent;

    // BUGFIX (2026-05-31): visual parity with `friend_chat_screen` —
    // simple TextField with `filled: true` + `BorderSide.none`, no
    // double-bordered AnimatedContainer, no focus glow, no oversized
    // attachment chrome. The "+" button uses the same 38x38 footprint
    // as the friend chat's audio recorder button so the input row
    // height matches end-to-end.
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── + button (non-admin only) — ChatPlusMenu ────────────────────
          if (!isAdmin)
            ChatPlusMenu(
              onImageTap: widget.onPickGallery,
              onDocumentTap: () {},
              onStickerTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Stickers coming soon')),
                );
              },
            ),

          // ── Text input field ─────────────────────────────────────────────
          Expanded(
            child: TextField(
              controller: widget.chatController,
              style: TextStyle(color: c.textPrimary, fontSize: 14),
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              onChanged: widget.onChanged,
              onSubmitted: (_) => widget.onSend(),
              decoration: InputDecoration(
                hintText: isAdmin ? 'Admin message...' : 'Type a message...',
                hintStyle: TextStyle(color: c.textTertiary),
                filled: true,
                fillColor: c.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // ── Send button ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hasText ? accentColor : accentColor.withValues(alpha: 0.3),
            ),
            child: IconButton(
              icon: widget.isUploading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.isDark ? Colors.black : Colors.white,
                      ),
                    )
                  : Icon(
                      Icons.send_outlined,
                      color: _hasText
                          ? (c.isDark ? Colors.black : Colors.white)
                          : (c.isDark ? Colors.black45 : Colors.white60),
                      size: 20,
                    ),
              onPressed: (_hasText && !widget.isUploading) ? widget.onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: colors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _AttachButton({
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 0.8 : 0.3,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.08),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
      ),
    );
  }
}

class VendorPayeeDetails extends ConsumerWidget {
  final String paymentMethod;
  final String accountLabel;
  final String accountDetail;
  final String? deepLink;
  final String? termsNote;

  const VendorPayeeDetails({
    super.key,
    required this.paymentMethod,
    required this.accountLabel,
    required this.accountDetail,
    this.deepLink,
    this.termsNote,
  });

  String? _appLink(String method) {
    final m = method.toLowerCase();
    if (m.contains('cashapp')) return 'https://cash.app/';
    if (m.contains('paypal')) return 'https://www.paypal.me/';
    if (m.contains('venmo')) return 'https://venmo.com/';
    if (m.contains('zelle')) return null;
    return null;
  }

  Future<void> _launchDeepLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final link = deepLink ?? _appLink(paymentMethod);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                'VENDOR PAYMENT INFO',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paymentMethod,
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  accountLabel,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  accountDetail,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.accent),
                    foregroundColor: colors.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy Tag',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Clipboard.setData(ClipboardData(
                        text: '$accountLabel\n$accountDetail'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Account details copied'),
                        backgroundColor: colors.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
              if (link != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor:
                          colors.isDark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: Text(
                      'Open ${_appLabel(paymentMethod)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: () => _launchDeepLink(link),
                  ),
                ),
              ],
            ],
          ),
          if (termsNote != null && termsNote!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: colors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    termsNote!,
                    style: TextStyle(
                        color: colors.textTertiary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _appLabel(String method) {
    final m = method.toLowerCase();
    if (m.contains('cashapp')) return 'CashApp';
    if (m.contains('paypal')) return 'PayPal';
    if (m.contains('venmo')) return 'Venmo';
    return 'App';
  }
}

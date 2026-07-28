import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/screens/upload_proof.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:azaman/widgets/chat_interface.dart';
import 'package:azaman/widgets/trade_disclaimer.dart';
import 'package:azaman/widgets/rate_lock_disclaimer.dart';
import 'package:azaman/widgets/draggable_timer_pill.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/platform_config_provider.dart';
import 'package:azaman/services/platform_config_service.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';

import 'package:go_router/go_router.dart';
import 'package:azaman/config.dart';
import 'package:azaman/screens/trade_summary_screen.dart';
import 'package:azaman/widgets/dual_currency_text.dart';
import 'package:hugeicons_pro/hugeicons.dart';


class ActiveTradeScreen extends ConsumerStatefulWidget {
  final double amount;
  final String orderId;
  final String paymentMethod;

  const ActiveTradeScreen({
    super.key,
    this.amount = 0.0,
    this.orderId = "Pending",
    this.paymentMethod = "Bank Transfer",
  });

  @override
  ConsumerState<ActiveTradeScreen> createState() => _ActiveTradeScreenState();
}

class _ActiveTradeScreenState extends ConsumerState<ActiveTradeScreen> {
  // ============================================================
  // Phase P3: Use the UNIFIED socket from SocketService.
  // No more duplicate socket instance.
  // ============================================================
  late IO.Socket socket;
  late String _cleanTradeId;
  // FIX: Cache provider reference for safe access in dispose().
  // Using ref.read() in dispose() throws 'Bad state: Cannot use ref
  // after the widget was disposed'. We grab the reference once in
  // initState() and reuse it in dispose().
  late final TradeProvider _cachedTradeProvider;

  // --- TRADE STATE ---
  double _tradeAmount = 0.0;
  String _tradePaymentMethod = "Bank Transfer";
  bool _isAccepted = false;
  bool _isChatOpen = false;
  bool _isPaid = false;
  bool _isDisputed = false;
  bool _vendorIsTyping = false;
  int _secondsRemaining = 900;
  bool _isExpired = false;
  bool _disposed = false; // FIX: Guard against setState after dispose
  DateTime? _paidAt;
  // BUGFIX (2026-05-27): the timer is now anchored to the BE's
  // canonical `Trade.expiresAt`, not `createdAt + 15min`. The previous
  // anchor ignored timer extensions entirely — the BE writes the new
  // deadline to `expiresAt` on every successful `extend_time` socket
  // event, but the FE was recomputing remaining time from `createdAt +
  // 15min` on every tick, wiping the extension within 1 second. Reading
  // from `expiresAt` is correct by construction: a 15-min trade that
  // hasn't been extended has `expiresAt = createdAt + 15min`, an
  // extended trade has whatever the server says.
  DateTime? _tradeExpiresAt;
  Timer? _timer;

  // --- DYNAMIC PAYMENT DATA ---
  Map<String, dynamic> _paymentData = {
    'details': '',
    'deepLink': '',
    'note': 'Please proceed with payment according to the selected method. Do not include crypto-related words in the memo.',
  };

  // Chat Messages State
  final List<Map<String, dynamic>> _messages = [];

  final GlobalKey _pillKey = GlobalKey();
  final GlobalKey _chatInputKey = GlobalKey();
  final GlobalKey _extendChipKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _cleanTradeId = widget.orderId.replaceAll('#', '');
    _tradeAmount = widget.amount;
    _tradePaymentMethod = widget.paymentMethod;

    // FIX: Cache the TradeProvider reference for safe access in dispose().
    _cachedTradeProvider = ref.read(tradeProvider);

    // Use the SHARED SocketService socket (proven to work for balance/notifications)
    final sharedSocket = SocketService.instance.rawSocket;
    if (sharedSocket == null) {
      debugPrint('🚨 [trade_chat] Shared socket is NULL — initializing now');
      SocketService.instance.init(ref);
    }
    socket = SocketService.instance.rawSocket!;
    debugPrint('🔌 [trade_chat] Using shared socket. Connected: ${socket.connected}, ID: ${socket.id}');

    // Join the trade room — emit on every connect (not just initial)
    void joinRooms() {
      final auth = ref.read(authProvider);
      debugPrint('🔌 [trade_chat] Joining trade_$_cleanTradeId as user ${auth.user?.id}');
      socket.emit('join_trade', _cleanTradeId);
      socket.emit('join_trade_chat', {
        'tradeId': _cleanTradeId,
        'userId': auth.user?.id,
      });
    }

    if (socket.connected) {
      joinRooms();
    }
    socket.onConnect((_) {
      debugPrint('🔌 [trade_chat] Socket connected event fired');
      joinRooms();
    });

    _setupSocketListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTradeState();
    });

    _startTimer();
  }

  /// Sets up all socket listeners on the SHARED socket instance.
  void _setupSocketListeners() {
    socket.on('new_trade_message', _onNewMessage);
    socket.on('new_message', _onNewMessage); // REST endpoint emits this
    socket.on('user_typing_trade', _onVendorTyping);
    socket.on('trade_update', _onTradeUpdate);
    socket.on('messages_read_update', _onMessagesRead);
    // CHAT DEBUG: optimistic-reconcile listeners
    socket.on('message_saved', _onMessageSaved);
    socket.on('message_delivered', _onMessageDelivered);
    socket.on('message_error', _onMessageError);
    socket.on('time_extended', _onTimeExtended);
    // BUGFIX (2026-05-31): listen for `message_updated` so time-extension
    // request cards (Grant/Decline) flip to their resolved state on both
    // sides when the vendor responds. Without this the buttons stayed
    // live and a vendor could grant the same request multiple times.
    socket.on('message_updated', _onMessageUpdated);
  }

  void _onNewMessage(dynamic data) {
    debugPrint('💬 [active_trade] new_trade_message: ${data.toString()}');
    if (!mounted) return;
    // Dedup: skip if we already have this DB id
    if (data['id'] != null && _messages.any((m) => m['id'] == data['id'])) return;
    // Also dedup by tempId (our own optimistic message coming back)
    if (data['tempId'] != null && _messages.any((m) => m['tempId'] == data['tempId'])) return;

    // Determine sender role — backend sends senderId as int or sender as object
    final auth = ref.read(authProvider);
    final myId = auth.user?.id;
    final senderId = data['senderId'] ?? data['sender']?['id'] ?? data['sender'];
    final isMyMessage = senderId == myId || senderId?.toString() == myId?.toString();

    // BUGFIX (2026-05-31): system cards like TIME_EXTENSION_REQUEST and
    // TIME_EXTENSION_GRANTED need to render on BOTH sides, including
    // the side that triggered them. Skipping based on senderId alone
    // would hide the request card from the user who initiated it (and
    // there's no optimistic add for these cards). Only skip when this
    // looks like a regular text/image bubble that was already added
    // optimistically.
    final rawText = (data['text'] ?? data['content'] ?? '').toString();
    final isExtensionCard = rawText.contains('TIME_EXTENSION_REQUEST') ||
        rawText.contains('TIME_EXTENSION_GRANTED');

    if (isMyMessage && !isExtensionCard) {
      // Regular bubble, already added optimistically.
      return;
    }

    final senderRole = isMyMessage ? 'user' : 'vendor';

    setState(() {
      _messages.add({
        "id": data['id'],
        "sender": senderRole,
        "text": rawText,
        "type": data['messageType']?.toString().toLowerCase() ?? "text",
        "imagePath": data['imagePath'],
        "mediaUrl": data['mediaUrl'],
        "createdAt": data['createdAt'] ?? data['time'],
        "status": "read"
      });
    });
  }

  // Sender-side: replace the optimistic bubble with the persisted one.
  void _onMessageSaved(dynamic data) {
    debugPrint('✅ [active_trade] message_saved: ${data['id']}');
    if (!mounted) return;
    final tempId = data['tempId']?.toString();
    if (tempId == null) return;
    setState(() {
      for (final m in _messages) {
        if (m['tempId'] == tempId) {
          m['id'] = data['id'];
          m['status'] = 'sent';
          m['createdAt'] = data['createdAt'];
        }
      }
    });
  }

  void _onMessageDelivered(dynamic data) {
    if (!mounted) return;
    setState(() {
      for (final m in _messages) {
        if (m['id'] == data['id'] || m['tempId'] == data['tempId']) {
          m['status'] = 'delivered';
        }
      }
    });
  }

  void _onMessageError(dynamic data) {
    debugPrint('❌ [active_trade] message_error: ${data.toString()}');
    if (!mounted) return;
    final tempId = data['tempId']?.toString();
    setState(() {
      for (final m in _messages) {
        if (m['tempId'] == tempId) m['status'] = 'failed';
      }
    });
  }

  void _onMessageUpdated(dynamic data) {
    if (!mounted) return;
    final id = data['id'];
    final newContent = data['content']?.toString();
    if (id == null || newContent == null) return;
    setState(() {
      for (final m in _messages) {
        if (m['id'] == id || m['id']?.toString() == id.toString()) {
          m['text'] = newContent;
          m['content'] = newContent;
        }
      }
    });
  }

  void _onVendorTyping(dynamic data) {
    if (mounted) setState(() => _vendorIsTyping = data['isTyping']);
  }

  void _onTradeUpdate(dynamic data) {
    if (!mounted) return;
    setState(() {
      if (data['status'] == 'PENDING_PAYMENT') _isAccepted = true;
      if (data['status'] == 'COMPLETED') _showSuccessOverlay();
      if (data['status'] == 'DISPUTED') _isDisputed = true;
    });

    // If vendor just accepted (status = PENDING_PAYMENT), refetch to get expiresAt
    if (data['status'] == 'PENDING_PAYMENT') {
      _syncTradeState();
    }

    // If expiresAt was sent in the event, sync the timer immediately
    if (data['expiresAt'] != null) {
      final parsed = DateTime.tryParse(data['expiresAt'].toString());
      if (parsed != null) {
        setState(() {
          _tradeExpiresAt = parsed.toLocal();
          _recomputeRemaining();
        });
      }
    }
  }

  void _requestTimeExtension() async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    const addedMinutes = 15;
    socket.emit('extend_time', {
      'tradeId': _cleanTradeId,
      'addedMinutes': addedMinutes,
    });
    // BUGFIX (2026-05-27): the previous version locally added
    // `addedMinutes * 60` to `_secondsRemaining` AND then the BE's
    // `time_extended` socket event ALSO added the same amount when it
    // arrived, so requesting +15 actually gave +30 to whoever clicked
    // the chip. The optimistic local bump is now removed — we wait for
    // the server's `time_extended` ack, which carries the canonical
    // `newExpiresAt` and is the single source of truth.
    _showRippleMerge(addedMinutes, fromChip: true);
  }

  void _onTimeExtended(dynamic data) {
    if (!mounted) return;
    final addedMinutes = (data['addedMinutes'] as num?)?.toInt() ?? 15;
    // Adopt the server-canonical new deadline. The BE persists this to
    // `Trade.expiresAt`, so a future re-open of this screen will read
    // the same value back.
    final newExpires = data['newExpiresAt']?.toString();
    if (newExpires != null) {
      final parsed = DateTime.tryParse(newExpires);
      if (parsed != null) {
        _tradeExpiresAt = parsed.toLocal();
      }
    } else if (_tradeExpiresAt != null) {
      // Fallback for older BE deploys that don't echo newExpiresAt:
      // shift the local deadline by addedMinutes.
      _tradeExpiresAt =
          _tradeExpiresAt!.add(Duration(minutes: addedMinutes));
    }
    _isExpired = false;
    _startTimer();
    _showRippleMerge(addedMinutes, fromChip: false);
  }

  void _showRippleMerge(int addedMinutes, {bool fromChip = false}) {
    final RenderBox? pillBox = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    if (pillBox == null || !pillBox.attached) return;

    final Offset pillPos = pillBox.localToGlobal(Offset.zero);
    final Size pillSize = pillBox.size;
    final Size screenSize = MediaQuery.of(context).size;

    double startX, startY;
    if (fromChip && _extendChipKey.currentContext != null) {
      final RenderBox? chipBox = _extendChipKey.currentContext?.findRenderObject() as RenderBox?;
      if (chipBox != null && chipBox.attached) {
        final Offset chipPos = chipBox.localToGlobal(Offset.zero);
        startX = chipPos.dx;
        startY = chipPos.dy;
      } else {
        startX = 24;
        startY = screenSize.height - 160;
      }
    } else {
      startX = 24;
      startY = screenSize.height - 160;
    }

    final OverlayState overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return _RippleMergeAnimation(
          addedMinutes: addedMinutes,
          startX: startX,
          startY: startY,
          endX: pillPos.dx + pillSize.width / 2 - 40,
          endY: pillPos.dy + pillSize.height / 2 - 20,
          onComplete: () {
            entry.remove();
          },
        );
      },
    );
    overlay.insert(entry);
  }

  void _onMessagesRead(dynamic data) {
    if (mounted) {
      setState(() {
        for (var msg in _messages) {
          if (msg['status'] == 'sent') {
            msg['status'] = 'read';
          }
        }
      });
    }
  }

  Future<void> _syncTradeState() async {
    try {
      final auth = ref.read(authProvider);
      final token = auth.user?.token;
      final currentUserId = auth.user?.id;

      final response = await apiClient.get('/trades/$_cleanTradeId');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // BUGFIX (2026-05-27): anchor the escrow timer to the BE's
        // canonical `Trade.expiresAt`, not `createdAt + 15min`. The
        // previous anchor never honoured extensions — every tick the
        // remaining time was recomputed from createdAt and any
        // `extend_time` ack was wiped within 1 second. `expiresAt` is
        // the single source of truth on the BE (updated atomically on
        // every successful extend_time emit) and a fresh sync should
        // always read it.
        if (data['expiresAt'] != null) {
          final parsed = DateTime.tryParse(data['expiresAt'].toString());
          if (parsed != null) {
            _tradeExpiresAt = parsed.toLocal();
            _recomputeRemaining();
            _startTimer();
          }
        } else if (data['createdAt'] != null) {
          // Fallback for older BE deploys that don't return expiresAt:
          // synthesise from createdAt + selectedTimeframe (defaults to
          // 15 min).
          final parsed = DateTime.tryParse(data['createdAt'].toString());
          if (parsed != null) {
            final minutes = (data['selectedTimeframe'] as num?)?.toInt() ?? 15;
            _tradeExpiresAt =
                parsed.toLocal().add(Duration(minutes: minutes));
            _recomputeRemaining();
            _startTimer();
          }
        }

        if (data['status'] == 'COMPLETED') {
          if (mounted) _transitionToSummary(backendData: data);
          return;
        }

        if (mounted) {
          setState(() {
            // Fix: Store live trade amount from backend
            if (data['amountFiat'] != null) {
              _tradeAmount = (data['amountFiat'] as num).toDouble();
            }
            if (data['paymentMethod'] != null) {
              _tradePaymentMethod = data['paymentMethod'].toString();
            }

            if (data['status'] == 'PAID') {
              _isPaid = true;
              _isAccepted = true;
              _paidAt = DateTime.tryParse(data['paidAt'] ?? "");
            }
            if (data['status'] == 'PENDING_PAYMENT') {
              _isAccepted = true;
            }
            if (data['status'] == 'DISPUTED') {
              _isDisputed = true;
              _isPaid = true;
            }

            if (data['vendorPaymentDetails'] != null) {
              if (data['vendorPaymentDetails'] is Map) {
                _paymentData = data['vendorPaymentDetails'];
              } else {
                _paymentData['details'] = data['vendorPaymentDetails'];
              }
            }

            // Load chat history
            if (data['messages'] != null && data['messages'] is List) {
              _messages.clear();

              for (var msg in data['messages']) {
                String senderRole;
                final int senderId = int.tryParse(msg['senderId']?.toString() ?? '0') ?? 0;

                if (senderId == int.tryParse(currentUserId.toString())) {
                  senderRole = 'user';
                } else if ((msg['text'] ?? '').contains("SYSTEM ADMIN")) {
                  senderRole = 'admin';
                } else {
                  senderRole = 'vendor';
                }

                _messages.add({
                  // BUGFIX (2026-05-27): include the BE id when loading
                  // history so the `_onNewMessage` dedup check (which
                  // ignores entries without an id) doesn't double-render
                  // a message when the realtime push arrives after the
                  // history fetch completes. Mid-conversation reloads
                  // were producing duplicate bubbles for any message
                  // that landed during the sync round-trip.
                  "id": msg['id'],
                  "sender": senderRole,
                  "text": msg['text'] ?? msg['content'] ?? "",
                  "type": msg['imagePath'] != null ? 'image' : 'text',
                  "imagePath": msg['imagePath'],
                  // Preserve both `time` (formatted, used by the bubble
                  // template) and `createdAt` (raw, used by the new
                  // `_onNewMessage` to compare timestamps) so realtime
                  // matches don't fall back to the no-id branch.
                  "time": _formatTime(msg['createdAt']),
                  "createdAt": msg['createdAt'],
                  "status": "read"
                });
              }
            }

            if (_messages.isEmpty) {
              _messages.add({
                "sender": "vendor",
                "text": "Hello! I am online and ready to confirm your payment.",
                "time": "Just now",
                "type": "text",
                "status": "read"
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
    }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return "Just now";
    try {
      final date = DateTime.parse(dateStr).toLocal();
      String hour = date.hour > 12
          ? (date.hour - 12).toString()
          : (date.hour == 0 ? "12" : date.hour.toString());
      String min = date.minute.toString().padLeft(2, '0');
      String ampm = date.hour >= 12 ? "PM" : "AM";
      return "$hour:$min $ampm";
    } catch (e) {
      return "Just now";
    }
  }

  String _formatDetailKey(String key) {
    // Convert camelCase to readable: "accountNumber" → "Account No."
    final mapped = {
      'email': 'Email',
      'phone': 'Phone',
      'cashtag': 'Cashtag',
      'username': 'Username',
      'bankName': 'Bank',
      'accountNumber': 'Account No.',
      'routingNumber': 'Routing No.',
      'fullName': 'Full Name',
      'country': 'Country',
      'accountTag': 'Tag',
    };
    return mapped[key] ?? key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}').trim();
  }

  String _getPaymentDetailsCopyText() {
    final buffer = StringBuffer();
    buffer.writeln(_tradePaymentMethod);
    for (final e in _paymentData.entries) {
      if (e.key != 'details' && e.key != 'deepLink' && e.key != 'note' && e.key != 'methodType' && e.value != null && e.value.toString().isNotEmpty) {
        buffer.writeln('${_formatDetailKey(e.key)}: ${e.value}');
      }
    }
    return buffer.toString().trim();
  }

  void _showUserTimeExtensionRequest() {
    final colors = ref.read(themeProvider).colors;
    final controller = TextEditingController(text: '15');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(HugeIconsSolid.clock01, color: const Color(0xFFFFB800), size: 22),
                  const SizedBox(width: 10),
                  Text('Request More Time', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Text('How many more minutes do you need? (max 120)', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: TextStyle(color: colors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: '15',
                  suffixText: 'minutes',
                  suffixStyle: TextStyle(color: colors.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.divider)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final mins = int.tryParse(controller.text);
                    if (mins == null || mins <= 0 || mins > 120) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a value between 1 and 120 minutes'), backgroundColor: Colors.red),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    try {
                      final response = await apiClient.post('/trades/extend', {
                        'tradeId': _cleanTradeId,
                        'addedMinutes': mins,
                        'isRequest': true,
                      });
                      if (response.statusCode == 200 && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: const Text('✓ Request sent to vendor'), backgroundColor: const Color(0xFF02C076)),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Send Request', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _transitionToSummary({Map<String, dynamic>? backendData}) {
    if (!mounted) return;

    final summaryData = {
      'tradeId': _cleanTradeId,
      'amountFiat': _tradeAmount,
      'paymentMethod': _tradePaymentMethod,
      'completedAt': backendData?['completedAt'],
    };

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => TradeSummaryScreen(
          tradeData: summaryData,
          isVendor: false,
        ),
      ),
    );
  }

  void _showDisputeDialog(BuildContext context) {
    final TextEditingController reasonController = TextEditingController();
    final auth = ref.read(authProvider);
    final trade = ref.read(tradeProvider);
    final colors = ref.read(themeProvider).colors;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(HugeIconsSolid.alertCircle, color: colors.danger, size: 28),
              const SizedBox(width: 10),
              Text("Open Dispute", style: TextStyle(color: colors.danger, fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            Text("This will freeze all assets in escrow and summon an Admin to review this trade.",
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: reasonController,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: "Describe the issue (e.g., Paid but vendor unresponsive)",
                hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () async {
                  if (reasonController.text.isEmpty) return;
                  Navigator.pop(ctx);

                  bool success = await trade.disputeTrade(
                      _cleanTradeId, reasonController.text, auth.token!);

                  if (success && mounted) {
                    setState(() => _isDisputed = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text("Dispute Raised. Assets Frozen."), backgroundColor: colors.danger),
                    );
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text("Failed to raise dispute."), backgroundColor: colors.danger),
                    );
                  }
                },
                child: const Text("SUBMIT DISPUTE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePaymentAction({bool isSharing = false}) async {
    // FIX: Cache ref.read() BEFORE any async gap to prevent dispose crash.
    final colors = ref.read(themeProvider).colors;

    String url = _paymentData['deepLink'] ?? "";
    String handle =
        _tradePaymentMethod.split(' - ').last.replaceAll('\$', '');

    if (url.isEmpty) {
      if (_tradePaymentMethod.contains("CashApp"))
        url = "https://cash.app/\$$handle/${_tradeAmount}";
      if (_tradePaymentMethod.contains("PayPal"))
        url = "https://www.paypal.me/$handle/${_tradeAmount}";
    }

    if (isSharing) {
      await Share.share(
          "Please pay \$${_tradeAmount} for Azaman Trade ${widget.orderId}. Method: ${_tradePaymentMethod}");
    } else {
      if (url.isNotEmpty && await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication);
      } else {
        Clipboard.setData(ClipboardData(text: _tradePaymentMethod));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text("Account details copied to clipboard!"),
              backgroundColor: colors.success));
        }
      }
    }
  }

  // ============================================================
  // PHASE 14.5 FIX: Escrow timer anchored to trade.expiresAt.
  // The BE writes the canonical deadline to `Trade.expiresAt`, updated
  // atomically on every successful `extend_time` socket event. The FE
  // simply mirrors it. Revisiting mid-trade shows the correct remaining
  // time (or EXPIRED if elapsed); extensions land instantly without
  // being wiped on the next tick.
  // ============================================================
  // Timer race-fix: if the backend anchor hasn't arrived yet, decrement
  // the local cached value so the user sees a visible countdown from
  // the initial 15:00 instead of a frozen clock. Once _syncTradeState()
  // populates _tradeExpiresAt the true remaining value replaces the
  // cached one.
  void _recomputeRemaining({bool tick = false}) {
    if (_tradeExpiresAt != null) {
      final remaining =
          _tradeExpiresAt!.difference(DateTime.now()).inSeconds;
      _secondsRemaining = remaining > 0 ? remaining : 0;
    } else if (tick && _secondsRemaining > 0) {
      _secondsRemaining -= 1;
    }
    _isExpired = _secondsRemaining <= 0;
  }

  void _startTimer() {
    _recomputeRemaining();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed || !mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _recomputeRemaining(tick: true);
        if (_secondsRemaining <= 0) {
          _secondsRemaining = 0;
          _isExpired = true;
          timer.cancel();
        }
      });
    });
  }

  void _showSuccessOverlay() {
    HapticFeedback.heavyImpact();
    final colors = ref.read(themeProvider).colors;
    final Color fg = colors.isDark ? Colors.black : Colors.white;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset('assets/animations/success.json',
                  width: 180, height: 180, repeat: false),
              Text("Payment Confirmed!",
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                  "The vendor has successfully received your payment and released the assets.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: colors.textSecondary, fontSize: 13)),
              const SizedBox(height: 25),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: fg,
                    minimumSize: const Size(double.infinity, 45),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  Navigator.pop(context);
                  _transitionToSummary();
                },
                child: Text("VIEW RECEIPT",
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.textPrimary),
        leading: IconButton(
          icon: Icon(HugeIconsSolid.arrowLeft01, color: colors.textPrimary),
          onPressed: () {
            // BUGFIX (2026-05-31): pop only if there's a real route
            // underneath this one. The previous `pushNamedAndRemoveUntil`
            // fallback called into Navigator's onGenerateRoute which is
            // not wired with GoRouter, producing the blank-screen
            // symptom when the trade was opened from a notification
            // that had cleared the stack via `context.go`. Now we use
            // GoRouter's `go('/')` which routes back to splash → which
            // re-enters MainWrapper through its normal auth path.
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              // No back stack — opened via stack-clearing deep link.
              // Send the user to splash, which will re-resolve auth and
              // land on MainWrapper.
              context.go('/');
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                _isDisputed
                    ? "Trade Disputed"
                    : _isPaid
                        ? "Awaiting Release"
                        : _isAccepted
                            ? "Please make payment"
                            : "Waiting for Vendor",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary)),
            Text(widget.orderId,
                style: TextStyle(
                    fontSize: 10,
                    color: colors.textTertiary,
                    fontFamily: 'monospace')),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
                _isChatOpen ? HugeIconsSolid.informationCircle : HugeIconsSolid.bubbleChat,
                color: colors.accent),
            onPressed: () => setState(() => _isChatOpen = !_isChatOpen),
          ),
          IconButton(
            icon: Icon(HugeIconsSolid.alertCircle, color: colors.danger),
            onPressed: () => _showDisputeDialog(context),
            tooltip: "Report Problem",
          )
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (!_isChatOpen) const TradeDisclaimer(compact: true),
              if (!_isChatOpen) RateLockDisclaimer(
                compact: true,
                lockedRate: ref.read(tradeProvider).yellowCardRate,
                lockExpiresAt: _tradeExpiresAt,
              ),
              if (_isDisputed && !_isChatOpen) _buildDisputeBanner(),
              Expanded(
                child: _isChatOpen
                    ? _buildChatInterface(colors)
                    : (_isPaid && !_isDisputed)
                        ? _buildAwaitingReleaseInterface(colors)
                        : _isDisputed
                            ? _buildDisputedInterface()
                            : _buildMainInterface(colors),
              ),
              if (_isPaid && !_isChatOpen && !_isDisputed)
                _buildAppealSection(colors),
            ],
          ),
          if (!_isDisputed)
            DraggableTimerPill(
              secondsRemaining: _secondsRemaining,
              isExpired: _isExpired,
              isDisputed: _isDisputed,
              colors: colors,
              pillKey: _pillKey,
            ),
        ],
      ),
      bottomNavigationBar:
          (_isAccepted && !_isChatOpen && !_isPaid && !_isDisputed)
              ? _buildBottomAction(colors)
              : null,
    );
  }

  // --- PINNED CHAT INTERFACE ---
  Widget _buildChatInterface(AzamanColors colors) {
    return Column(
      children: [
        // The Golden Pinned Terms Banner
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.1),
            border: Border(
                bottom: BorderSide(color: colors.accent.withValues(alpha: 0.3))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(HugeIconsSolid.pin, color: colors.accent, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("VENDOR TERMS OF TRADE",
                        style: TextStyle(
                            color: colors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      _paymentData['note']?.toString().isNotEmpty == true
                          ? _paymentData['note']
                          : "Please proceed with the payment according to the selected method.",
                      style: TextStyle(color: colors.textPrimary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Time extension removed from user side — handled via chat request system
        Expanded(
          child: ChatInterface(
            socket: socket,
            tradeId: _cleanTradeId,
            myRole: 'user',
            messages: _messages,
            isTyping: _vendorIsTyping,
            onTimeExtension: _showUserTimeExtensionRequest,
            onSendMessage: (text, mediaUrl) async {
              final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
              final auth = ref.read(authProvider);
              final numericUserId = auth.user?.id ?? '0';

              if (text.isNotEmpty) {
                // Optimistic add
                setState(() {
                  _messages.add({
                    "tempId": tempId,
                    "sender": "user",
                    "text": text,
                    "type": "text",
                    "status": "sending",
                    "createdAt": DateTime.now().toIso8601String(),
                  });
                });

                // Use REST endpoint (proven pattern from friend chat)
                try {
                  final response = await apiClient.post('/chat/send', {
                    'tradeId': _cleanTradeId,
                    'text': text,
                  });
                  if (response.statusCode == 201) {
                    final body = jsonDecode(response.body);
                    final savedMsg = body['message'];
                    setState(() {
                      for (final m in _messages) {
                        if (m['tempId'] == tempId) {
                          m['id'] = savedMsg?['id'];
                          m['status'] = 'sent';
                          m['createdAt'] = savedMsg?['createdAt'] ?? m['createdAt'];
                        }
                      }
                    });
                  } else {
                    setState(() {
                      for (final m in _messages) {
                        if (m['tempId'] == tempId) m['status'] = 'failed';
                      }
                    });
                  }
                } catch (e) {
                  debugPrint('❌ [trade_chat] Send failed: $e');
                  setState(() {
                    for (final m in _messages) {
                      if (m['tempId'] == tempId) m['status'] = 'failed';
                    }
                  });
                }
              } else if (mediaUrl != null) {
                socket.emit('send_trade_message', {
                  'tradeId': _cleanTradeId,
                  'content': mediaUrl,
                  'senderId': numericUserId,
                  'messageType': 'IMAGE_PROOF',
                  'tempId': tempId,
                });
                setState(() {
                  _messages.add({
                    "tempId": tempId,
                    "sender": "user",
                    "text": "",
                    "type": "image",
                    "mediaUrl": mediaUrl,
                    "status": "sending",
                    "createdAt": DateTime.now().toIso8601String(),
                  });
                });
              }
            },
          ),
        ),
      ],
    );
  }

  // --- AWAITING RELEASE INTERFACE ---
  Widget _buildAwaitingReleaseInterface(AzamanColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 100,
                  width: 100,
                  child: CircularProgressIndicator(
                      color: colors.success.withValues(alpha: 0.2),
                      strokeWidth: 8),
                ),
                Icon(HugeIconsSolid.lock, color: colors.success, size: 40),
              ],
            ),
            const SizedBox(height: 30),
            Text("Awaiting Vendor Release",
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Text(
              "You have successfully marked this trade as paid. The vendor has been notified and is verifying your payment.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colors.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text(
              "Your assets are safely locked in Azaman Escrow.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // Phase ADMIN-CONTROL-2-FE: Vendor earnings preview helper.
  double _calcVendorEarnings(double tradeAmountUsdc, PlatformConfig config) {
    final platformFee = tradeAmountUsdc * config.p2pFeePct;
    final vendorSplit = tradeAmountUsdc >= config.tierThreshold
        ? config.vendorShareOver1k
        : config.vendorShareUnder1k;
    return platformFee * vendorSplit;
  }

  // --- MAIN DETAILS INTERFACE ---
  Widget _buildMainInterface(AzamanColors colors) {
    final config = ref.watch(platformConfigProvider);
    final auth = ref.watch(authProvider);
    final isVendor = (auth.user?.role ?? '').toUpperCase() == 'VENDOR';
    final tradeAmountUsdc = _tradeAmount;
    final expectedEarnings = _calcVendorEarnings(tradeAmountUsdc, config);
    final vendorSplitPct = tradeAmountUsdc >= config.tierThreshold
        ? config.vendorShareOver1k
        : config.vendorShareUnder1k;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Amount to Pay",
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DualCurrencyText(
                usdc: _tradeAmount,
                style: TextStyle(color: colors.accent, fontSize: 32, fontWeight: FontWeight.bold),
              ),
              IconButton(
                  onPressed: () => _handlePaymentAction(isSharing: true),
                  icon: Icon(HugeIconsSolid.share01, color: colors.textSecondary)),
            ],
          ),
          const SizedBox(height: 25),
          if (!_isAccepted)
            Center(
                child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: colors.accent)))
          else ...[
            Text("Payment Method",
                style: TextStyle(
                    color: colors.textPrimary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildHorizontalSteps(colors),
            const SizedBox(height: 30),
            // HIGHLIGHTED VENDOR DETAILS BOX
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: colors.accent.withValues(alpha: 0.4), width: 1.5)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(HugeIconsSolid.wallet01,
                          color: colors.accent, size: 16),
                      const SizedBox(width: 8),
                      Text("VENDOR ACCOUNT DETAILS",
                          style: TextStyle(
                              color: colors.accent.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                          child: Text(_tradePaymentMethod,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold))),
                      Container(
                        decoration: BoxDecoration(
                            color: colors.textPrimary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8)),
                        child: IconButton(
                            icon: Icon(HugeIconsSolid.copy01, color: colors.accent, size: 20),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              final copyText = _getPaymentDetailsCopyText();
                              Clipboard.setData(ClipboardData(text: copyText));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: const Text(
                                        "Account details copied!"),
                                    backgroundColor: colors.success),
                              );
                            }),
                      ),
                    ],
                  ),
                  // Show actual vendor account details
                  if (_paymentData.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ..._paymentData.entries
                        .where((e) => e.key != 'details' && e.key != 'deepLink' && e.key != 'note' && e.key != 'methodType' && e.value != null && e.value.toString().isNotEmpty)
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      _formatDetailKey(e.key),
                                      style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      e.value.toString(),
                                      style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                  ],
                  Divider(color: colors.divider, height: 30),
                  // Phase ADMIN-CONTROL-2-FE: persistent vendor earnings row
                  if (isVendor && tradeAmountUsdc > 0) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Your earnings',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '+${expectedEarnings.toStringAsFixed(4)} USDC',
                                style: TextStyle(
                                  color: colors.success,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '(${(vendorSplitPct * 100).toStringAsFixed(0)}% of platform fee)',
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
                    Divider(color: colors.divider, height: 16),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(HugeIconsSolid.informationCircle,
                          color: colors.textTertiary, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              "Terms: ${_paymentData['note'] ?? 'Please pay directly to the account listed above.'}",
                              style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                  height: 1.5))),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildLaunchButton(colors),
          ],
        ],
      ),
    );
  }

  Widget _buildHorizontalSteps(AzamanColors colors) {
    List<Map<String, dynamic>> steps = [
      {"icon": HugeIconsSolid.copy01, "label": "Copy Info"},
      {"icon": HugeIconsSolid.share01, "label": "Open App"},
      {"icon": Icons.credit_card_outlined, "label": "Pay Vendor"},
      {"icon": Icons.check_circle_outline, "label": "Upload Proof"},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(steps.length, (index) {
          bool isLast = index == steps.length - 1;
          return Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.card,
                      border: Border.all(color: colors.divider),
                    ),
                    child: Icon(steps[index]['icon'],
                        size: 18, color: colors.accent),
                  ),
                  const SizedBox(height: 8),
                  Text(steps[index]['label'],
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              if (!isLast)
                Container(
                  width: 30,
                  height: 2,
                  color: colors.divider,
                  margin: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 15),
                  alignment: Alignment.topCenter,
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildLaunchButton(AzamanColors colors) {
    final Color fg = colors.isDark ? Colors.black : Colors.white;
    return ElevatedButton.icon(
      onPressed: () {
        HapticFeedback.selectionClick();
        _handlePaymentAction(isSharing: false);
      },
      icon: Icon(HugeIconsSolid.share01, color: fg, size: 18),
      style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: fg,
          minimumSize: const Size(double.infinity, 55),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12))),
      label: Text("OPEN PAYMENT APP",
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: fg,
              fontSize: 14)),
    );
  }

  Widget _buildTimerHeader(AzamanColors colors) {
    final String timeStr = _isExpired
        ? "EXPIRED"
        : "${(_secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}";

    // Priority: dispute > expired > normal countdown
    final Color accent = _isDisputed
        ? colors.danger
        : (_isExpired ? colors.danger : colors.accent);
    final String label = _isDisputed
        ? "DISPUTE ACTIVE"
        : (_isExpired ? "PAYMENT WINDOW CLOSED" : "Payment Time Left");

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: accent.withValues(alpha: 0.12),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  _isExpired ? HugeIconsSolid.clock01 : HugeIconsSolid.clock01,
                  size: 16,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Text(
                    label,
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4)),
              ],
            ),
            Text(timeStr,
                style: TextStyle(
                    color: _isExpired ? colors.danger : colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: _isExpired ? 14 : 18,
                    letterSpacing: _isExpired ? 1.2 : 0,
                    fontFamily: 'monospace')),
          ]),
    );
  }

  Widget _buildDisputeBanner() {
    final colors = ref.read(themeProvider).colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.1),
        border: Border(bottom: BorderSide(color: colors.danger.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(HugeIconsSolid.lock, color: colors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Trade Locked. An Admin is reviewing this dispute.",
              style: TextStyle(color: colors.danger, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisputedInterface() {
    final colors = ref.read(themeProvider).colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: colors.danger.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(Icons.shield_outlined, color: colors.danger, size: 56),
            ),
            const SizedBox(height: 24),
            Text("Dispute Active", style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              "All actions are frozen. An Admin has been notified and will review the trade chat and payment evidence before making a ruling.",
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 10),
            Text("Assets remain safely locked in escrow.", textAlign: TextAlign.center,
                style: TextStyle(color: colors.warning, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.accent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => setState(() => _isChatOpen = true),
                icon: Icon(HugeIconsSolid.bubbleChat, color: colors.accent, size: 18),
                label: Text("Open Chat", style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppealSection(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ElevatedButton(
        onPressed: !_isDisputed
            ? () {
                HapticFeedback.heavyImpact();
                _showDisputeDialog(context);
              }
            : null,
        style: ElevatedButton.styleFrom(
            backgroundColor: _isDisputed
                ? colors.textTertiary.withValues(alpha: 0.4)
                : colors.danger.withValues(alpha: 0.85),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 55),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
        child: Text(
            _isDisputed
                ? "APPEAL UNDER REVIEW"
                : "VENDOR NOT RELEASING? APPEAL HERE",
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      ),
    );
  }

  Widget _buildBottomAction(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor: colors.success,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 55),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
        onPressed: () {
          HapticFeedback.mediumImpact();
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      UploadProofScreen(orderId: widget.orderId)));
        },
        child: const Text("I HAVE TRANSFERRED THE MONEY",
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true; // FIX: Prevent timer callback from calling setState

    // FIX: Cancel the timer FIRST to prevent any further callbacks
    _timer?.cancel();
    _timer = null;

    // Remove our listeners from the shared socket
    socket.off('new_trade_message', _onNewMessage);
    socket.off('new_message', _onNewMessage);
    socket.off('user_typing_trade', _onVendorTyping);
    socket.off('trade_update', _onTradeUpdate);
    socket.off('messages_read_update', _onMessagesRead);
    socket.off('message_saved', _onMessageSaved);
    socket.off('message_delivered', _onMessageDelivered);
    socket.off('message_error', _onMessageError);
    socket.off('time_extended', _onTimeExtended);
    socket.off('message_updated', _onMessageUpdated);

    // Tell the provider we left this trade room
    _cachedTradeProvider.leaveTradeRoom(_cleanTradeId);

    super.dispose();
  }
}

class _RippleMergeAnimation extends ConsumerStatefulWidget {
  final int addedMinutes;
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final VoidCallback onComplete;

  const _RippleMergeAnimation({
    required this.addedMinutes,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.onComplete,
  });

  @override
  ConsumerState<_RippleMergeAnimation> createState() => _RippleMergeAnimationState();
}

class _RippleMergeAnimationState extends ConsumerState<_RippleMergeAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _position;
  late Animation<double> _scale;
  late Animation<double> _rippleScale;
  late Animation<double> _rippleOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _position = Tween<Offset>(
      begin: Offset(widget.startX, widget.startY),
      end: Offset(widget.endX, widget.endY),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.easeInOut),
    ));

    _scale = Tween<double>(begin: 1.0, end: 0.55).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeInOut),
      ),
    );

    _rippleOpacity = Tween<double>(begin: 0.0, end: 1.0,).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 0.75, curve: Curves.easeOut),
      ),
    );

    _rippleScale = Tween<double>(begin: 0.5, end: 2.5).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AzamanColors>() ?? ref.read(themeProvider).colors;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            // Animated bubble flying from source to pill
            Positioned(
              left: _position.value.dx,
              top: _position.value.dy,
              child: Transform.scale(
                scale: _scale.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.success,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colors.success.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    '+${widget.addedMinutes}m',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),

            // Expanding ripple ring at pill destination
            if (_controller.value >= 0.6)
              Positioned(
                left: widget.endX - 20,
                top: widget.endY - 20,
                child: Opacity(
                  opacity: (1.0 - _rippleOpacity.value).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: _rippleScale.value,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.success.withValues(alpha: 0.15),
                        border: Border.all(
                          color: colors.success.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Inner pulsing dot at pill destination
            if (_controller.value >= 0.7)
              Positioned(
                left: widget.endX - 6,
                top: widget.endY - 6,
                child: Opacity(
                  opacity: _rippleOpacity.value,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.success,
                      boxShadow: [
                        BoxShadow(
                          color: colors.success.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/platform_config_provider.dart';
import 'package:azaman/services/platform_config_service.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/services/api_client.dart';
import 'dart:async';
import 'package:azaman/widgets/chat_interface.dart';
import 'package:azaman/widgets/trade_disclaimer.dart';
import 'package:azaman/widgets/rate_lock_disclaimer.dart';
import 'package:azaman/widgets/draggable_timer_pill.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/utils/biometric_gate.dart';
import 'package:azaman/config.dart';

import 'package:azaman/screens/trade_summary_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:azaman/widgets/azaman_network_image.dart';


class VendorTradeExecution extends ConsumerStatefulWidget {
  final Map<String, dynamic> tradeData;

  const VendorTradeExecution({super.key, required this.tradeData});

  @override
  ConsumerState<VendorTradeExecution> createState() => _VendorTradeExecutionState();
}

class _VendorTradeExecutionState extends ConsumerState<VendorTradeExecution> {
  bool _isAccepted = false;
  bool _paymentReceived = false;
  bool _isChatOpen = false;
  final bool _userIsTyping = false;
  bool _isReleasing = false;
  bool _isDisputed = false;

  bool _hasViewedProof = false;
  String? _paymentProofUrl;
  bool _isLoadingTrade = true;
  bool _disposed = false; // FIX: Guard against setState after dispose

  final List<Map<String, dynamic>> _messages = [];

  late String _cleanTradeId;
  String _vendorTerms = "";
  // FIX: Cache provider reference for safe access in dispose().
  // Using ref.read() in dispose() throws 'Bad state: Cannot use ref
  // after the widget was disposed'. We grab the reference once in
  // Phase P3: Cache the unified socket reference for safe access in dispose().
  late final TradeProvider _cachedTradeProvider;
  late final IO.Socket _cachedSocket;

  int _secondsRemaining = 900;
  bool _isExpired = false;
  DateTime? _tradeCreatedAt;
  DateTime? _tradeExpiresAt;
  Timer? _timer;
  static const int _escrowWindowSeconds = 15 * 60;
  final GlobalKey _pillKey = GlobalKey();
  final GlobalKey _chatInputKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    HapticFeedback.vibrate();

    // FIX (Bug 2): Resolve tradeId from EITHER 'tradeId' or 'id' key.
    // The notification screen passes the full backend trade object which uses
    // 'id', while the vendor_dashboard socket handler uses 'tradeId'.
    final rawId = (widget.tradeData['tradeId'] ?? widget.tradeData['id'] ?? '').toString();
    _cleanTradeId = rawId.replaceAll('#', '');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // FIX: Cache the TradeProvider reference for safe access in dispose().
      _cachedTradeProvider = ref.read(tradeProvider);
      _cachedSocket = SocketService.instance.rawSocket!;

      _cachedTradeProvider.joinTradeRoom(_cleanTradeId);
      _fetchLiveTradeDetails();

      _cachedSocket.on('payment_confirmed', _onPaymentConfirmed);
      _cachedSocket.on('new_trade_message', _onNewMessage);
      _cachedSocket.on('new_message', _onNewMessage);
      _cachedSocket.on('messages_read_update', _onMessagesRead);
      _cachedSocket.on('trade_update', _onTradeUpdate);
      _cachedSocket.on('trade_disputed', _onTradeDisputed);
      _cachedSocket.on('message_saved', _onMessageSaved);
      _cachedSocket.on('message_delivered', _onMessageDelivered);
      _cachedSocket.on('message_error', _onMessageError);
      _cachedSocket.on('time_extended', _onTimeExtended);
      _cachedSocket.on('message_updated', _onMessageUpdated);
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

  void _onMessageSaved(dynamic data) {
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
    if (!mounted) return;
    final tempId = data['tempId']?.toString();
    setState(() {
      for (final m in _messages) {
        if (m['tempId'] == tempId) m['status'] = 'failed';
      }
    });
  }

  // --- Named handlers for clean disposal ---

  void _onPaymentConfirmed(dynamic data) {
    if (data['tradeId'].toString() == _cleanTradeId) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _paymentReceived = true;
          if (data['proofUrl'] != null) {
            _paymentProofUrl = data['proofUrl'];
          } else {
            _fetchLiveTradeDetails();
          }
          _messages.add({
            "sender": "system",
            "text": "Buyer has marked the trade as PAID.",
            "type": "text",
            "time": "Just now",
            "status": "read"
          });
        });
      }
    }
  }

  void _onNewMessage(dynamic data) {
    debugPrint('💬 [vendor_exec] new_trade_message: ${data.toString()}');
    if (mounted) {
      if (data['id'] != null && _messages.any((m) => m['id'] == data['id'])) return;
      setState(() {
        _messages.add({
          "id": data['id'],
          "sender": data['sender'] == "buyer"
              ? "user"
              : (data['sender'] == 'admin' ? 'admin' : 'vendor'),
          "text": data['text'] ?? data['content'] ?? "",
          "type": data['type'] ?? "text",
          "imagePath": data['imagePath'],
          "mediaUrl": data['mediaUrl'],
          "createdAt": data['createdAt'] ?? data['time'],
          "status": "read"
        });
      });
      if (data['sender'] == 'user' || data['sender'] == 'buyer') {
        _cachedSocket.emit('mark_messages_read',
            {'tradeId': _cleanTradeId, 'readerId': 'vendor'});
      }
    }
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

  void _onTradeUpdate(dynamic data) {
    if (!mounted) return;
    setState(() {
      if (data['status'] == 'PENDING_PAYMENT') _isAccepted = true;
      if (data['status'] == 'DISPUTED') {
        _isDisputed = true;
        _messages.add({
          "sender": "system",
          "text": "This trade has been DISPUTED. An admin will review shortly.",
          "type": "text",
          "time": "Just now",
          "status": "read"
        });
      }
      if (data['status'] == 'COMPLETED') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => TradeSummaryScreen(
              tradeData: widget.tradeData,
              isVendor: true,
            ),
          ),
        );
      }
    });

    // Refetch trade after vendor accepts to get expiresAt
    if (data['status'] == 'PENDING_PAYMENT') {
      _fetchLiveTradeDetails();
    }

    // Sync timer if expiresAt is in the event
    if (data['expiresAt'] != null) {
      final parsed = DateTime.tryParse(data['expiresAt'].toString());
      if (parsed != null && mounted) {
        setState(() {
          _tradeExpiresAt = parsed.toLocal();
          _recomputeRemaining();
        });
      }
    }
  }

  void _onTradeDisputed(dynamic data) {
    if (data['tradeId'].toString() == _cleanTradeId && mounted) {
      HapticFeedback.heavyImpact();
      setState(() {
        _isDisputed = true;
        _messages.add({
          "sender": "system",
          "text": "A dispute has been opened on this trade. All actions are frozen until an admin resolves it.",
          "type": "text",
          "time": "Just now",
          "status": "read"
        });
      });
    }
  }

  Future<void> _fetchLiveTradeDetails() async {
    try {
      final auth = ref.read(authProvider);
      final currentUserId = auth.user?.id;

      final response = await apiClient.get('/trades/$_cleanTradeId');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          // Phase: Use expiresAt as canonical source for timer (synced with user)
          if (data['expiresAt'] != null) {
            final parsed = DateTime.tryParse(data['expiresAt'].toString());
            if (parsed != null) {
              _tradeExpiresAt = parsed.toLocal();
              _recomputeRemaining();
              _startTimer();
            }
          } else if (data['createdAt'] != null) {
            // Fallback for trades without expiresAt set yet
            final parsed = DateTime.tryParse(data['createdAt'].toString());
            if (parsed != null) {
              _tradeCreatedAt = parsed.toLocal();
              _recomputeRemaining();
              _startTimer();
            }
          }

          // Phase H3 review-pass fix: when the screen was opened from a
          // socket payload (vendor_dashboard.dart `new_trade_request`), the
          // `tradeData` map only carries `amount` (stringified fiat) — no
          // `amountCrypto`/`crypto`/`currency`. The release-crypto sheet
          // reads typed fields from this map and would otherwise show
          // "Releasing 0.00 USDT" on the highest-stakes confirm in the app.
          // Backfill the typed fields here, so by the time the vendor
          // taps "Release crypto" the sheet has real numbers.
          if (data['amountFiat'] != null) {
            widget.tradeData['amountFiat'] =
                (data['amountFiat'] as num).toDouble();
          }
          if (data['amountCrypto'] != null) {
            widget.tradeData['amountCrypto'] =
                (data['amountCrypto'] as num).toDouble();
          }
          if (data['crypto'] != null) {
            widget.tradeData['crypto'] = data['crypto'].toString();
          }
          if (data['currency'] != null) {
            widget.tradeData['currency'] = data['currency'].toString();
          }
          if (data['paymentMethod'] != null) {
            widget.tradeData['paymentMethod'] =
                data['paymentMethod'].toString();
          }

          setState(() {
            _isAccepted = data['status'] != 'NEW' && data['status'] != 'PENDING';
            if (data['status'] == 'PAID') _paymentReceived = true;
            if (data['status'] == 'DISPUTED') {
              _isDisputed = true;
              _paymentReceived = true;
            }

            if (data['proofUrl'] != null && data['proofUrl'].toString().isNotEmpty) {
              _paymentProofUrl = data['proofUrl'].toString().startsWith('http')
                  ? data['proofUrl']
                  : '${AppConfig.baseUrl}${data['proofUrl']}';
            }

            if (data['vendorPaymentDetails'] != null && data['vendorPaymentDetails'] is Map) {
              _vendorTerms = data['vendorPaymentDetails']['note']?.toString() ?? "";
            }

            if (data['messages'] != null && data['messages'] is List) {
              _messages.clear();

              for (var msg in data['messages']) {
                String senderRole;
                final int senderId = int.tryParse(msg['senderId']?.toString() ?? '0') ?? 0;

                if (senderId == int.tryParse(currentUserId.toString())) {
                  senderRole = 'vendor';
                } else if ((msg['text'] ?? '').contains("SYSTEM ADMIN")) {
                  senderRole = 'admin';
                } else {
                  senderRole = 'user';
                }

                _messages.add({
                  "id": msg['id'],
                  "sender": senderRole,
                  "text": msg['text'] ?? msg['content'] ?? "",
                  "type": msg['imagePath'] != null ? 'image' : 'text',
                  "imagePath": msg['imagePath'],
                  "time": _formatTime(msg['createdAt']),
                  "createdAt": msg['createdAt'],
                  "status": "read"
                });
              }
            }

            _isLoadingTrade = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching trade details: $e");
      if (mounted) setState(() => _isLoadingTrade = false);
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

  void _showProofImage() {
    final colors = ref.read(themeProvider).colors;
    setState(() => _hasViewedProof = true);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: Icon(Icons.cancel_outlined, color: colors.textPrimary, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AzamanNetworkImage(imageUrl: 
                  _paymentProofUrl!,
                  fit: BoxFit.contain,
                  errorWidget: (context, error, stackTrace) {
                    return Container(
                      height: 300, width: double.infinity, color: colors.card,
                      child: Center(
                        child: Text(
                          "Error loading receipt image.\nPlease ask user to send in chat.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.danger),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processApiRelease() async {
    setState(() => _isReleasing = true);
    final colors = ref.read(themeProvider).colors;

    try {
      final response = await apiClient.post('/p2p/complete', {"tradeId": _cleanTradeId});

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text("Assets Released! User credited with AZM."),
            backgroundColor: colors.success,
          ));

          // Phase H3 — was: Navigator.pop (popping the AlertDialog) +
          // pushReplacement (replacing VendorTradeExecution). The sheet is
          // now closed before this method runs, so the pop would have eaten
          // VendorTradeExecution. We just pushReplacement directly — the
          // back-stack collapses from [Home, Vendor] to [Home, Summary].
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => TradeSummaryScreen(
                tradeData: widget.tradeData,
                isVendor: true,
              ),
            ),
          );
        }
      } else {
        final resData = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(resData['message'] ?? "Error releasing"),
            backgroundColor: colors.danger,
          ));
          // Phase H3 — was: Navigator.pop. Removed: the sheet is already
          // closed, popping again would bounce the vendor off the trade
          // screen on a transient backend hiccup, losing chat context.
          // The snackbar is enough; user stays on VendorTradeExecution
          // and can retry.
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Network Error: $e"),
          backgroundColor: colors.danger,
        ));
        // Phase H3 — same fix as the 4xx branch above.
      }
    } finally {
      if (mounted) setState(() => _isReleasing = false);
    }
  }

  void _showVendorTimeExtension() {
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
                  const Icon(Icons.access_time, color: Color(0xFFFFB800), size: 22),
                  const SizedBox(width: 10),
                  Text('Extend Trade Time', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Add extra minutes to the timer (max 120). The user will be notified.', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
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
              const SizedBox(height: 12),
              // Quick options
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [15, 30, 60, 120].map((m) => GestureDetector(
                  onTap: () => controller.text = m.toString(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.divider),
                    ),
                    child: Text('$m min', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                )).toList(),
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
                        'isRequest': false,
                      });
                      if (response.statusCode == 200 && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('✓ Time extended by $mins min'), backgroundColor: const Color(0xFF02C076)),
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
                  child: const Text('Extend Time', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptTrade() async {
    HapticFeedback.heavyImpact();
    try {
      final response = await apiClient.post('/trades/accept', {'tradeId': _cleanTradeId});
      if (response.statusCode == 200) {
        setState(() => _isAccepted = true);
        // Refetch the trade to get the new expiresAt set by the backend
        await _fetchLiveTradeDetails();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Trade accepted — timer started'), backgroundColor: ref.read(themeProvider).colors.success),
          );
        }
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to accept trade');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _declineTrade() async {
    final colors = ref.read(themeProvider).colors;
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Decline Trade', style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Please provide a reason for declining:', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              style: TextStyle(color: colors.textPrimary),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Reason...',
                hintStyle: TextStyle(color: colors.textTertiary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colors.divider)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: colors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Decline', style: TextStyle(color: colors.danger, fontWeight: FontWeight.bold))),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await apiClient.post('/trades/decline', {
        'tradeId': _cleanTradeId,
        'reason': reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : 'Vendor declined the trade.',
      });
      if (response.statusCode == 200) {
        if (mounted) Navigator.pop(context);
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to decline trade');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleReleaseCrypto() {
    final colors = ref.read(themeProvider).colors;

    if (_isDisputed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Trade is under dispute. Actions are frozen."),
        backgroundColor: colors.danger,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (!_hasViewedProof) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("You must view the payment proof before releasing assets.",
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: colors.danger,
        behavior: SnackBarBehavior.floating,
      ));
      HapticFeedback.vibrate();
      return;
    }

    AzamanHaptics.nav();

    // Phase H3 — replaced AlertDialog with a slide-to-confirm bottom sheet.
    // The slide is biometric-gated when the user has biometric lock enabled
    // in Settings (opt-in). The sheet is dismissible by sliding down — the
    // release fires only on a full slide, never on a tap. This is the
    // highest-stakes financial confirm in the app: it irreversibly transfers
    // crypto from the vendor's escrow to the buyer.
    final slideKey = GlobalKey<SlideToConfirmState>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: !_isReleasing,
      enableDrag: !_isReleasing,
      builder: (sheetCtx) {
        return _ReleaseCryptoSheet(
          slideKey: slideKey,
          tradeData: widget.tradeData,
          isReleasing: _isReleasing,
          onConfirmed: () {
            // Pop the sheet first so the spinner-overlay snackbar doesn't
            // race with the sheet dismiss animation.
            Navigator.of(sheetCtx).pop();
            AzamanBiometricGate.run(
              context,
              () async {
                if (!mounted) return;
                // _processApiRelease() flips _isReleasing itself in a
                // try/finally, so we don't need to flip it here.
                await _processApiRelease();
              },
              reason: 'Authenticate to release crypto',
              // The sheet is already closed by the time this fires, so
              // resetting its slider via slideKey is a no-op (the State
              // has been disposed). Kept here for completeness — if the
              // sheet ever stays open during the gate run, this will
              // re-arm it correctly.
              onCancelled: () => slideKey.currentState?.reset(),
            );
          },
        );
      },
    );
  }

  void _recomputeRemaining({bool tick = false}) {
    // Prefer expiresAt (synced from server, also updates on time extensions)
    if (_tradeExpiresAt != null) {
      final remaining = _tradeExpiresAt!.difference(DateTime.now()).inSeconds;
      _secondsRemaining = remaining > 0 ? remaining : 0;
    } else if (_tradeCreatedAt != null) {
      final elapsed = DateTime.now().difference(_tradeCreatedAt!).inSeconds;
      final remaining = _escrowWindowSeconds - elapsed;
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

  void _onTimeExtended(dynamic data) {
    if (!mounted) return;
    final addedMinutes = (data['addedMinutes'] as num?)?.toInt() ?? 15;
    _secondsRemaining += addedMinutes * 60;
    _isExpired = false;
    _startTimer();
    _showRippleMerge(addedMinutes);
  }

  void _showRippleMerge(int addedMinutes) {
    final RenderBox? pillBox = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    if (pillBox == null || !pillBox.attached) return;
    final Offset pillPos = pillBox.localToGlobal(Offset.zero);
    final Size pillSize = pillBox.size;
    final OverlayState overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return _VendorRippleMerge(
          addedMinutes: addedMinutes,
          startX: 24,
          startY: MediaQuery.of(context).size.height - 160,
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

  void _showDisputeDialog() {
    // FIX: Cache ref.read() BEFORE showing the sheet to prevent dispose crash.
    final colors = ref.read(themeProvider).colors;
    final auth = ref.read(authProvider);
    final trade = ref.read(tradeProvider);
    final token = auth.user?.token ?? '';
    final reasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
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
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: colors.divider, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(Icons.error_outline, color: colors.danger, size: 28),
                    const SizedBox(width: 12),
                    Text("Open a Dispute",
                        style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Describe the issue. An admin will review this trade and all chat history. Assets will be frozen until resolved.",
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  maxLines: 4,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: "e.g. Buyer claims payment but I haven't received it...",
                    hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
                    filled: true,
                    fillColor: colors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.danger,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      final reason = reasonController.text.trim();
                      if (reason.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: const Text("Please provide a reason for the dispute."),
                          backgroundColor: colors.warning,
                          behavior: SnackBarBehavior.floating,
                        ));
                        return;
                      }

                      Navigator.pop(ctx);

                      // FIX: Use pre-cached auth/trade — no ref.read() here.
                      final success = await trade.disputeTrade(_cleanTradeId, reason, token);

                      if (mounted) {
                        if (success) {
                          HapticFeedback.heavyImpact();
                          setState(() => _isDisputed = true);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text("Dispute filed. An admin will review shortly."),
                            backgroundColor: colors.warning,
                            behavior: SnackBarBehavior.floating,
                          ));
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text("Failed to file dispute. Try again."),
                            backgroundColor: colors.danger,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    },
                    child: Text("Submit Dispute",
                        style: TextStyle(color: colors.isDark ? Colors.black : Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Critical: this is a WATCH (no listen:false in original code) — using
    // ref.watch to preserve the rebuild-on-trade-state-change behaviour.
    final trade = ref.watch(tradeProvider);
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Text(_isChatOpen ? "Chat with Buyer" : "Order in Progress",
            style: TextStyle(fontSize: 14, color: colors.textPrimary, fontWeight: FontWeight.bold)),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () {
            if (_isChatOpen) {
              setState(() => _isChatOpen = false);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          if (_paymentReceived && !_isDisputed)
            IconButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                _showDisputeDialog();
              },
              icon: Icon(Icons.flag_outlined, color: colors.danger),
              tooltip: "Open Dispute",
            ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _isChatOpen = !_isChatOpen);
            },
            icon: Icon(
              _isChatOpen ? Icons.note_outlined : Icons.chat_bubble_outline,
              color: colors.accent,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_isDisputed) _buildDisputeBanner(colors),
              if (!_isChatOpen) _buildStatusHeader(colors),
              if (!_isChatOpen) const TradeDisclaimer(compact: true),
              if (!_isChatOpen) const RateLockDisclaimer(compact: true),
              Expanded(
                child: _isChatOpen
                    ? _buildChatInterface(trade, colors)
                    : _isDisputed
                        ? _buildDisputedInterface(colors, trade)
                        : SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                _buildTradeDetails(colors),
                                const SizedBox(height: 20),
                                if (_isAccepted) _buildPaymentVerificationSection(colors),
                              ],
                            ),
                          ),
              ),
              if (!_isChatOpen && !_isDisputed) _buildActionBottomBar(trade, colors),
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
    );
  }

  // ============================================================
  // DISPUTE UI
  // ============================================================
  Widget _buildDisputeBanner(AzamanColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.15),
        border: Border(bottom: BorderSide(color: colors.danger.withValues(alpha: 0.4), width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: colors.danger, size: 18),
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

  Widget _buildDisputedInterface(AzamanColors colors, TradeProvider trade) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shield_outlined, color: colors.danger, size: 60),
            ),
            const SizedBox(height: 24),
            Text("Dispute Active",
                style: TextStyle(color: colors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              "All actions are frozen. An administrator is reviewing this trade and the full chat history.",
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.accent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => setState(() => _isChatOpen = true),
                icon: Icon(Icons.chat_bubble_outline, color: colors.accent),
                label: Text("Open Chat", style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CHAT INTERFACE
  // ============================================================
  Widget _buildChatInterface(TradeProvider trade, AzamanColors colors) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.1),
            border: Border(bottom: BorderSide(color: colors.accent.withValues(alpha: 0.3))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.push_pin_outlined, color: colors.accent, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("YOUR TERMS OF TRADE",
                        style: TextStyle(
                            color: colors.accent, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      _vendorTerms.isNotEmpty
                          ? _vendorTerms
                          : "Please verify payment in your account before releasing assets.",
                      style: TextStyle(color: colors.textPrimary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ChatInterface(
            socket: SocketService.instance.rawSocket!,
            tradeId: _cleanTradeId,
            myRole: 'vendor',
            messages: _messages,
            isTyping: _userIsTyping,
            onTimeExtension: _showVendorTimeExtension,
            onSendMessage: (text, mediaUrl) async {
              final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
              if (text.isNotEmpty) {
                // Optimistic add
                setState(() {
                  _messages.add({
                    "tempId": tempId,
                    "sender": "vendor",
                    "text": text,
                    "type": "text",
                    "status": "sending",
                    "createdAt": DateTime.now().toIso8601String(),
                  });
                });

                // Send via REST API (proven pattern)
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
                  debugPrint('❌ [vendor_chat] Send failed: $e');
                  setState(() {
                    for (final m in _messages) {
                      if (m['tempId'] == tempId) m['status'] = 'failed';
                    }
                  });
                }
              } else if (mediaUrl != null) {
                final auth = ref.read(authProvider);
                final numericUserId = auth.user?.id ?? '0';
                SocketService.instance.emit('send_trade_message', {
                  'tradeId': _cleanTradeId,
                  'content': mediaUrl,
                  'senderId': numericUserId,
                  'messageType': 'IMAGE_PROOF',
                  'tempId': tempId,
                });
                setState(() {
                  _messages.add({
                    "tempId": tempId,
                    "sender": "vendor",
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

  Widget _buildStatusHeader(AzamanColors colors) {
    String statusText;
    if (_isDisputed) {
      statusText = "TRADE UNDER DISPUTE";
    } else if (!_isAccepted) {
      statusText = "NEW TRADE REQUEST";
    } else if (_paymentReceived) {
      statusText = "PAYMENT MARKED AS PAID";
    } else {
      statusText = "Waiting for buyer payment";
    }

    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: (_isDisputed ? colors.danger : colors.accent).withValues(alpha: 0.1), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusText,
            style: TextStyle(
              color: _isDisputed ? colors.danger : colors.accent,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _isDisputed
                ? "All actions are frozen. An admin is reviewing this trade."
                : "Please verify the USD amount in your account before releasing.",
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Phase ADMIN-CONTROL-2-FE: Vendor earnings preview ────────────────────
  double _calcVendorEarnings(double tradeAmountUsdc, PlatformConfig config) {
    final platformFee = tradeAmountUsdc * config.p2pFeePct;
    final vendorSplit = tradeAmountUsdc >= config.tierThreshold
        ? config.vendorShareOver1k
        : config.vendorShareUnder1k;
    return platformFee * vendorSplit;
  }

  Widget _buildTradeDetails(AzamanColors colors) {
    final config = ref.watch(platformConfigProvider);
    final tradeAmountUsdc =
        (widget.tradeData['amountCrypto'] as num?)?.toDouble() ?? 0.0;
    final expectedEarnings = _calcVendorEarnings(tradeAmountUsdc, config);
    final vendorSplitPct = tradeAmountUsdc >= config.tierThreshold
        ? config.vendorShareOver1k
        : config.vendorShareUnder1k;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: colors.card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _rowDetail(
            'Amount to Receive',
            '\$${widget.tradeData['amount']}',
            colors,
            isBold: true,
          ),
          // Phase ADMIN-CONTROL-2-FE: earnings preview row
          if (tradeAmountUsdc > 0) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your earnings',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
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
          ],
          Divider(color: colors.divider, height: 30),
          _rowDetail('Buyer', widget.tradeData['userName'] ?? 'Buyer', colors),
          _rowDetail('Order ID', _cleanTradeId, colors),
        ],
      ),
    );
  }

  Widget _buildPaymentVerificationSection(AzamanColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("USER PAID TO:",
            style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.05),
            border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: colors.textTertiary),
              const SizedBox(width: 12),
              Text(widget.tradeData['paymentMethod'] ?? "Zelle / PayPal",
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        if (_paymentReceived && _paymentProofUrl != null) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _hasViewedProof ? colors.success : colors.accent, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _showProofImage,
              icon: Icon(_hasViewedProof ? Icons.check_circle_outline : Icons.image_outlined,
                  color: _hasViewedProof ? colors.success : colors.accent),
              label: Text(
                _hasViewedProof ? "PAYMENT PROOF VERIFIED" : "VIEW PAYMENT PROOF",
                style: TextStyle(
                    color: _hasViewedProof ? colors.success : colors.accent, fontWeight: FontWeight.bold),
              ),
            ),
          )
        ] else if (_paymentReceived && _paymentProofUrl == null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colors.danger, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Buyer marked as paid, but no receipt was found. Please ask them to send it in the chat.",
                    style: TextStyle(color: colors.danger, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        ]
      ],
    );
  }

  Widget _rowDetail(String label, String value, AzamanColors colors, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: isBold ? FontWeight.w900 : FontWeight.normal,
                  fontSize: isBold ? 18 : 13)),
        ],
      ),
    );
  }

  Widget _buildActionBottomBar(TradeProvider trade, AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.divider.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          if (!_isAccepted) ...[
            Expanded(child: _actionBtn("Decline", colors.card, colors.textPrimary, () {
              _declineTrade();
            })),
            const SizedBox(width: 15),
            Expanded(
              child: _actionBtn("Accept Trade", colors.accent, colors.isDark ? Colors.black : Colors.white, () {
                _acceptTrade();
              }),
            ),
          ] else ...[
            Expanded(
              child: _actionBtn(
                "I HAVE RECEIVED PAYMENT",
                _hasViewedProof ? colors.accent : colors.divider,
                _hasViewedProof ? (colors.isDark ? Colors.black : Colors.white) : colors.textTertiary,
                _handleReleaseCrypto,
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color bg, Color text, VoidCallback onTap) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true; // FIX: Prevent timer callback from calling setState

    // FIX: Cancel the timer FIRST to prevent any further callbacks
    _timer?.cancel();
    _timer = null;

    // FIX: Use cached references — no ref.read() calls in dispose().
    _cachedSocket.off('payment_confirmed', _onPaymentConfirmed);
    _cachedSocket.off('new_trade_message', _onNewMessage);
    _cachedSocket.off('messages_read_update', _onMessagesRead);
    _cachedSocket.off('trade_update', _onTradeUpdate);
    _cachedSocket.off('trade_disputed', _onTradeDisputed);
    _cachedSocket.off('message_saved', _onMessageSaved);
    _cachedSocket.off('message_delivered', _onMessageDelivered);
    _cachedSocket.off('message_error', _onMessageError);
    _cachedSocket.off('time_extended', _onTimeExtended);
    _cachedSocket.off('message_updated', _onMessageUpdated);

    _cachedTradeProvider.leaveTradeRoom(_cleanTradeId);

    super.dispose();
  }
}

class _VendorRippleMerge extends ConsumerStatefulWidget {
  final int addedMinutes;
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final VoidCallback onComplete;

  const _VendorRippleMerge({
    required this.addedMinutes,
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.onComplete,
  });

  @override
  ConsumerState<_VendorRippleMerge> createState() => _VendorRippleMergeState();
}

class _VendorRippleMergeState extends ConsumerState<_VendorRippleMerge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _position;
  late Animation<double> _scale;
  late Animation<double> _rippleOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _position = Tween<Offset>(
      begin: Offset(widget.startX, widget.startY),
      end: Offset(widget.endX, widget.endY),
    ).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.easeInOut)));

    _scale = Tween<double>(begin: 1.0, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.easeInOut)),
    );

    _rippleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.7, 1.0, curve: Curves.easeOut)),
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
    final colors = ref.read(themeProvider).colors;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned(
              left: _position.value.dx,
              top: _position.value.dy,
              child: Transform.scale(
                scale: _scale.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: colors.success.withValues(alpha: 0.4), blurRadius: 12)],
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
            if (_controller.value >= 0.7)
              Positioned(
                left: widget.endX - 20,
                top: widget.endY - 20,
                child: Opacity(
                  opacity: _rippleOpacity.value,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.success.withValues(alpha: 0.3),
                    ),
                    child: Center(
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.success.withValues(alpha: 0.6),
                        ),
                      ),
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


// ============================================================
// PHASE H3 — Slide-to-confirm release sheet
// ============================================================
//
// This sheet replaces the AlertDialog that previously gated the
// "I have received payment, release crypto" action. Three things
// changed:
//
// 1. The confirm UI is now a slide gesture, not a tap. A vendor
//    can't reflexively tap "Confirm" while distracted in a chat —
//    they have to deliberately drag the thumb across.
//
// 2. The action is biometric-gated when the user has enabled
//    biometric lock in Settings. This is the strongest financial
//    confirm in the app (irreversible asset transfer), so it
//    deserves the strongest pre-gate available on mobile.
//
// 3. The sheet shows a richer summary (amount, payment method,
//    the explicit warning) than the dialog could. The audit's
//    §11 brief called for this specifically.

class _ReleaseCryptoSheet extends ConsumerWidget {
  final Map<String, dynamic> tradeData;
  final bool isReleasing;
  final VoidCallback onConfirmed;
  final GlobalKey<SlideToConfirmState> slideKey;

  const _ReleaseCryptoSheet({
    required this.tradeData,
    required this.isReleasing,
    required this.onConfirmed,
    required this.slideKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    // Phase H3 review-pass fix: not every entry to this sheet routes the
    // raw backend trade JSON. The vendor-dashboard path stringifies the
    // amount into the `amount` key and drops the typed splits. Read the
    // V2 typed fields first (notification path), fall back to `amount`
    // (dashboard path) so the most common entry never shows zeros.
    final fiat = (tradeData['amountFiat'] as num?)?.toDouble() ??
        double.tryParse(tradeData['amount']?.toString() ?? '') ??
        0.0;
    final crypto = (tradeData['amountCrypto'] as num?)?.toDouble() ?? 0.0;
    final paymentMethod = (tradeData['paymentMethod'] ?? '').toString();
    final cryptoSymbol = (tradeData['crypto'] ?? 'USDT').toString();
    final currency = (tradeData['currency'] ?? 'USD').toString();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Row(
                children: [
                  Icon(Icons.key_outlined, color: colors.accent, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Release crypto',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'You are about to release crypto from escrow to the buyer. This cannot be undone.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4),
              ),

              const SizedBox(height: 20),

              // Amount summary card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryRow(
                      label: 'Releasing',
                      value: '${crypto.toStringAsFixed(2)} $cryptoSymbol',
                      colors: colors,
                      emphasized: true,
                    ),
                    const SizedBox(height: 10),
                    _SummaryRow(
                      label: 'Buyer paid',
                      value: '${fiat.toStringAsFixed(2)} $currency',
                      colors: colors,
                    ),
                    if (paymentMethod.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _SummaryRow(
                        label: 'Method',
                        value: paymentMethod,
                        colors: colors,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Final warning
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.warning.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: colors.warning, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Confirm only if the funds have actually arrived in your account. Do not release based on screenshots alone.',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Slide to confirm
              SlideToConfirm(
                key: slideKey,
                text: 'Slide to release crypto',
                backgroundColor: Colors.transparent,
                thumbColor: colors.success,
                isLoading: isReleasing,
                onConfirmed: onConfirmed,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final AzamanColors colors;
  final bool emphasized;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.colors,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: colors.textTertiary, fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: emphasized ? 16 : 13,
            fontWeight: emphasized ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

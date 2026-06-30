import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/widgets/chat_interface.dart';


class SpyGlassScreen extends ConsumerStatefulWidget {
  const SpyGlassScreen({super.key});

  @override
  ConsumerState<SpyGlassScreen> createState() => _SpyGlassScreenState();
}

class _SpyGlassScreenState extends ConsumerState<SpyGlassScreen> {
  final TextEditingController _tradeIdController = TextEditingController();
  bool _isSpying = false;
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  int _secondsRemaining = 900;
  bool _isExpired = false;

  IO.Socket? _socket;

  void _connectSpyRoom() {
    final tradeId = _tradeIdController.text.trim();
    if (tradeId.isEmpty) return;

    HapticFeedback.mediumImpact();

    final tp = ref.read(tradeProvider);
    _socket = SocketService.instance.rawSocket;

    _socket!.emit('join_admin_spy', tradeId);

    setState(() {
      _isSpying = true;
      _messages.clear();
      _secondsRemaining = 900;
      _isExpired = false;
    });
  }

  void _disconnectSpyRoom() {
    final tradeId = _tradeIdController.text.trim();
    if (tradeId.isEmpty) return;

    _socket?.emit('leave_admin_spy', tradeId);
    setState(() {
      _isSpying = false;
      _messages.clear();
    });
  }

  void _onSpyMessage(dynamic data) {
    if (!mounted) return;
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
        "status": "read",
      });
    });
  }

  void _onSpyTyping(dynamic data) {
    if (!mounted) return;
    setState(() => _isTyping = data['isTyping'] == true);
  }

  void _onSpyTimer(dynamic data) {
    if (!mounted) return;
    setState(() {
      _secondsRemaining = (data['secondsRemaining'] as num?)?.toInt() ?? _secondsRemaining;
      _isExpired = data['isExpired'] == true || _secondsRemaining <= 0;
    });
  }

  void _sendAdminIntervention(String text, String? mediaUrl) {
    final tradeId = _tradeIdController.text.trim();
    if (tradeId.isEmpty) return;

    final auth = ref.read(authProvider);
    final adminUserId = auth.user?.id ?? 0;

    setState(() {
      _messages.add({
        "sender": "admin",
        "text": text,
        "type": "ADMIN_INTERVENTION",
        "status": "sent",
        "createdAt": DateTime.now().toIso8601String(),
        "adminName": auth.user?.username ?? "Admin",
      });
    });

    _socket?.emit('send_trade_message', {
      'tradeId': tradeId,
      'text': text,
      'senderId': 'admin',
      'adminUserId': adminUserId,
      'type': 'ADMIN_INTERVENTION',
      'adminName': auth.user?.username ?? "Admin",
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final socket = SocketService.instance.rawSocket;
      socket?.on('spy_message', _onSpyMessage);
      socket?.on('spy_typing', _onSpyTyping);
      socket?.on('spy_timer', _onSpyTimer);
    });
  }

  @override
  void dispose() {
    if (_isSpying) {
      _socket?.emit('leave_admin_spy', _tradeIdController.text.trim());
    }
    final socket = SocketService.instance.rawSocket;
    socket?.off('spy_message', _onSpyMessage);
    socket?.off('spy_typing', _onSpyTyping);
    socket?.off('spy_timer', _onSpyTimer);
    _tradeIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.visibility_outlined, color: colors.danger, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              _isSpying ? "SPY GLASS: #${_tradeIdController.text}" : "SPY GLASS",
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () {
            _disconnectSpyRoom();
            Navigator.pop(context);
          },
        ),
        actions: [
          if (_isSpying)
            IconButton(
              icon: Icon(Icons.compress, color: colors.danger),
              tooltip: "Disconnect",
              onPressed: _disconnectSpyRoom,
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isSpying)
            _buildConnectPanel(colors)
          else ...[
            _buildSpyTimerBar(colors),
            Expanded(
              child: ChatInterface(
                socket: SocketService.instance.rawSocket!,
                tradeId: _tradeIdController.text,
                myRole: 'admin',
                messages: _messages,
                isTyping: _isTyping,
                onSendMessage: _sendAdminIntervention,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectPanel(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.danger.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.visibility_outlined, color: colors.danger, size: 52),
          ),
          const SizedBox(height: 24),
          Text(
            "Spy Glass & Intervention",
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Enter a trade ID to monitor the conversation in real-time.\nYou can also send ADMIN INTERVENTION messages.",
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _tradeIdController,
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              hintText: "Trade ID (e.g. 42)",
              hintStyle: TextStyle(color: colors.textTertiary),
              prefixIcon: Icon(Icons.tag, color: colors.accent),
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.accent.withOpacity(0.5)),
              ),
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _connectSpyRoom(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.danger,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _connectSpyRoom,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text(
                "CONNECT TO SPY ROOM",
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpyTimerBar(AzamanColors colors) {
    final String timeStr = _isExpired
        ? "EXPIRED"
        : "${(_secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}";

    final Color accent = _isExpired ? colors.danger : colors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: accent.withOpacity(0.08),
      child: Row(
        children: [
          Icon(
            _isExpired ? Icons.access_time : Icons.access_time,
            size: 14,
            color: accent,
          ),
          const SizedBox(width: 8),
          Text(
            _isExpired ? "TIMER EXPIRED" : "LIVE TIMER",
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            timeStr,
            style: TextStyle(
              color: _isExpired ? colors.danger : colors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// WAITING ROOM SCREEN — Phase N | Azaman V2
//
// Full-featured queue waiting room with:
//   - Animated queue position display (pulse + spin)
//   - Real-time socket listeners for queue_position_update & queue_promoted
//   - Auto-navigation to ActiveTradeScreen on promotion
//   - Leave Queue button wired to PUT /api/queue/:queueId/leave
//   - Warning banner about exchange rate finalization
//
// Socket events consumed:
//   queue_position_update → { queueId, position }
//   queue_promoted        → { queueId, tradeId }  (auto-nav to trade)
//   queue_update          → { queueId, status, lockedRate, adId }
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/marketplace_provider.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:azaman/screens/active_trade_screen.dart';

class WaitingRoomScreen extends ConsumerStatefulWidget {
  final int queuePosition;
  final String queueId;
  final String adId;

  const WaitingRoomScreen({
    super.key,
    this.queuePosition = 1,
    required this.queueId,
    required this.adId,
  });

  @override
  ConsumerState<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends ConsumerState<WaitingRoomScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _spinController;
  late Animation<double> _pulseAnim;
  late int _currentPosition;
  bool _isLeaving = false;
  bool _promoted = false;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.queuePosition;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Wire socket listeners for real-time queue updates
    _attachSocketListeners();
  }

  void _attachSocketListeners() {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;

    // Position update: another buyer ahead left or was promoted
    socket.on('queue_position_update', _handlePositionUpdate);

    // Promoted: your turn! Auto-navigate to active trade
    socket.on('queue_promoted', _handlePromotion);

    // Legacy queue_update event from queueController.processNextInQueue
    socket.on('queue_update', _handleQueueUpdate);
  }

  void _handlePositionUpdate(dynamic data) {
    if (!mounted) return;
    final raw = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    final queueId = raw['queueId']?.toString();
    if (queueId != widget.queueId) return;

    final newPosition = (raw['position'] as num?)?.toInt() ?? _currentPosition;
    setState(() => _currentPosition = newPosition);
    HapticFeedback.lightImpact();
  }

  void _handlePromotion(dynamic data) {
    if (!mounted || _promoted) return;
    final raw = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    final queueId = raw['queueId']?.toString();
    if (queueId != widget.queueId) return;

    _promoted = true;
    final tradeId = raw['tradeId']?.toString() ?? '';
    HapticFeedback.heavyImpact();

    if (tradeId.isNotEmpty) {
      // If the BE created a trade for us, navigate directly to it
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ActiveTradeScreen(orderId: '#$tradeId'),
        ),
      );
    } else {
      // Slot opened but no trade created yet — pop back so buyer can
      // re-initiate from the marketplace. Show success message.
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your turn! A trade slot is now open. Tap the ad to start.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _handleQueueUpdate(dynamic data) {
    if (!mounted || _promoted) return;
    final raw = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    final queueId = raw['queueId']?.toString();
    if (queueId != widget.queueId) return;

    final status = raw['status']?.toString();
    if (status == 'PROCESSED') {
      // This queue entry was processed — promoted to active trade
      _promoted = true;
      HapticFeedback.heavyImpact();
      final tradeId = raw['tradeId']?.toString() ?? '';

      if (tradeId.isNotEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ActiveTradeScreen(orderId: '#$tradeId'),
          ),
        );
      } else {
        // Slot opened — pop back to marketplace for re-initiation
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your turn! A trade slot is now open. Tap the ad to start.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _detachSocketListeners() {
    final socket = SocketService.instance.rawSocket;
    if (socket == null) return;
    socket.off('queue_position_update', _handlePositionUpdate);
    socket.off('queue_promoted', _handlePromotion);
    socket.off('queue_update', _handleQueueUpdate);
  }

  @override
  void dispose() {
    _detachSocketListeners();
    _pulseController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _leaveQueue() async {
    if (_isLeaving) return;
    setState(() => _isLeaving = true);

    try {
      await ref.read(adsProvider.notifier).leaveQueue(widget.queueId);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isLeaving = false);
        final colors = ref.read(themeProvider).colors;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to leave queue: ${e.toString()}',
              style: TextStyle(color: colors.textPrimary),
            ),
            backgroundColor: colors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        leading: const SizedBox.shrink(),
        title: Text(
          'WAITING ROOM',
          style: TextStyle(
            color: colors.accent,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAnimatedLoader(colors),
                      const SizedBox(height: 40),
                      _buildQueuePosition(colors),
                      const SizedBox(height: 24),
                      _buildWarningBanner(colors),
                    ],
                  ),
                ),
              ),
            ),
            _buildLeaveQueueButton(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedLoader(AzamanColors colors) {
    return AnimatedBuilder(
      animation: _spinController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _spinController.value * 3.14159 * 2,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.glow.withOpacity(0.15),
                width: 3,
              ),
            ),
            child: Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.glow.withOpacity(0.3),
                    width: 3,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colors.glow.withOpacity(0.6),
                          colors.glow.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQueuePosition(AzamanColors colors) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnim.value,
          child: Column(
            children: [
              Text(
                'You are #$_currentPosition in line',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _currentPosition == 1
                    ? "You're next \u2014 prepare for trade."
                    : '${_currentPosition - 1} buyers ahead of you',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWarningBanner(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.warning.withOpacity(0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Exchange rates finalize only when you enter the active trade.',
              style: TextStyle(
                color: colors.warning,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveQueueButton(AzamanColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.danger.withOpacity(0.15),
            foregroundColor: colors.danger,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.danger.withOpacity(0.4)),
            ),
            elevation: 0,
          ),
          onPressed: _isLeaving ? null : _leaveQueue,
          child: _isLeaving
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.danger),
                  ),
                )
              : const Text(
                  'LEAVE QUEUE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
        ),
      ),
    );
  }
}

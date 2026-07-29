import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/hologram_provider.dart';

/// A premium animated bank card sheet for sending and requesting money in chats.
class ChatTransferSheet extends ConsumerStatefulWidget {
  final String contactName;
  final bool initialIsRequest;
  const ChatTransferSheet({super.key, required this.contactName, this.initialIsRequest = false});

  @override
  ConsumerState<ChatTransferSheet> createState() => _ChatTransferSheetState();
}

class _ChatTransferSheetState extends ConsumerState<ChatTransferSheet>
    with SingleTickerProviderStateMixin {
  late bool _isRequest;
  String _amountStr = '';
  late AnimationController _sheenController;

  static const Color _cardGold = Color(0xFFD4AF37);
  static const Color _gradTopBase = Color(0xFF0E1116);
  static const Color _gradBottom = Color(0xFF05070A);

  @override
  void initState() {
    super.initState();
    _isRequest = widget.initialIsRequest;
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _sheenController.dispose();
    super.dispose();
  }

  void _onKeypadTap(String val) {
    if (val == '<') {
      if (_amountStr.isNotEmpty) {
        setState(() => _amountStr = _amountStr.substring(0, _amountStr.length - 1));
        HapticFeedback.lightImpact();
      }
      return;
    }
    if (val == '.' && _amountStr.contains('.')) return;
    if (_amountStr == '0' && val != '.') {
      setState(() => _amountStr = val);
    } else {
      final parts = _amountStr.split('.');
      if (parts.length == 2 && parts[1].length >= 2) return; // max 2 decimals
      setState(() => _amountStr += val);
    }
    HapticFeedback.lightImpact();
  }

  void _toggleMode() {
    setState(() => _isRequest = !_isRequest);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(hologramBalanceProvider);
    final double amount = double.tryParse(_amountStr) ?? 0.0;
    final bool canProceed = amount > 0 && (_isRequest || amount <= balance);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0C10),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          
          // Premium Card Area
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AspectRatio(
              aspectRatio: 1.586, // standard credit card ratio
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.alphaBlend(_cardGold.withValues(alpha: 0.16), _gradTopBase),
                              _gradBottom,
                            ],
                          ),
                          border: Border.all(color: _cardGold.withValues(alpha: 0.22), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: _cardGold.withValues(alpha: 0.14),
                              blurRadius: 28,
                              spreadRadius: -6,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: -60,
                      right: -40,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _cardGold.withValues(alpha: 0.04), width: 1),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -80,
                      right: -60,
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _cardGold.withValues(alpha: 0.03), width: 1.5),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: _CardSheen(controller: _sheenController, width: MediaQuery.of(context).size.width - 40),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _ModeToggle(isRequest: _isRequest, onToggle: _toggleMode),
                              Container(
                                width: 28,
                                height: 20,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  gradient: LinearGradient(
                                    colors: [
                                      _cardGold.withValues(alpha: 0.85),
                                      _cardGold.withValues(alpha: 0.45),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  'USDC',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _amountStr.isEmpty ? '0' : _amountStr,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 48,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.5,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _isRequest ? 'Requesting from ${widget.contactName}' : 'Sending to ${widget.contactName}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (!_isRequest)
                                Text(
                                  'Bal: \$${balance.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: amount > balance ? Colors.redAccent : Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Keypad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                _KeypadRow(['1', '2', '3'], _onKeypadTap),
                const SizedBox(height: 16),
                _KeypadRow(['4', '5', '6'], _onKeypadTap),
                const SizedBox(height: 16),
                _KeypadRow(['7', '8', '9'], _onKeypadTap),
                const SizedBox(height: 16),
                _KeypadRow(['.', '0', '<'], _onKeypadTap),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Action Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: GestureDetector(
              onTap: canProceed ? () => Navigator.pop(context, {'amount': amount, 'isRequest': _isRequest}) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: canProceed ? _cardGold : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  _isRequest ? 'Request \$${amount.toStringAsFixed(2)}' : 'Send \$${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: canProceed ? const Color(0xFF0E1116) : Colors.white.withValues(alpha: 0.3),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool isRequest;
  final VoidCallback onToggle;
  const _ModeToggle({required this.isRequest, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TogglePill(text: 'Send', isActive: !isRequest),
            _TogglePill(text: 'Request', isActive: isRequest),
          ],
        ),
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  final String text;
  final bool isActive;
  const _TogglePill({required this.text, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.5),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _KeypadRow extends StatelessWidget {
  final List<String> keys;
  final Function(String) onTap;
  const _KeypadRow(this.keys, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: keys.map((k) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(k),
          child: Container(
            width: 60,
            height: 50,
            alignment: Alignment.center,
            child: k == '<'
                ? Icon(HugeIconsStroke.arrowLeft01, color: Colors.white.withValues(alpha: 0.8), size: 24)
                : Text(
                    k,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        );
      }).toList(),
    );
  }
}

class _CardSheen extends StatelessWidget {
  final AnimationController controller;
  final double width;
  const _CardSheen({required this.controller, required this.width});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final t = Curves.easeInOutSine.transform(controller.value);
          final dx = -width * 0.7 + t * width * 1.9;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.rotate(
              angle: -0.4,
              child: Container(
                width: width * 0.28,
                height: width * 2.2,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      Color(0x0DFFFFFF),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

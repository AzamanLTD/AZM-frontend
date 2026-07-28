// =============================================================================
// AZAMAN V3 — TRANSFER MODAL (Bottom Sheet)
//
// Toggle between Send / Request funds to a friend.
// Features: amount input, reference field, balance display, insufficient funds
// warning, and a slide-to-confirm widget.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/friend_service.dart';
import 'package:azaman/utils/biometric_gate.dart';
import 'package:azaman/widgets/slide_to_confirm.dart';


class TransferModal extends ConsumerStatefulWidget {
  final String friendshipId;
  final String friendUsername;

  const TransferModal({
    super.key,
    required this.friendshipId,
    required this.friendUsername,
  });

  @override
  ConsumerState<TransferModal> createState() => _TransferModalState();
}

class _TransferModalState extends ConsumerState<TransferModal> {
  bool _isSendMode = true; // true = Send, false = Request
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final FriendService _service = FriendService();
  // Phase H3 — slide-key for biometric-cancel reset.
  final GlobalKey<SlideToConfirmState> _slideKey =
      GlobalKey<SlideToConfirmState>();

  bool _isLoading = false;
  bool _isSuccess = false;
  String? _error;

  double get _amount => double.tryParse(_amountController.text) ?? 0.0;

  double get _userBalance {
    final user = ref.read(authProvider).user;
    return user?.availableBalance ?? 0.0;
  }

  bool get _hasSufficientFunds => !_isSendMode || _amount <= _userBalance;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _executeTransfer() async {
    final token = ref.read(authProvider).user?.token;
    if (token == null) return;

    // Phase H6 BUGFIX (2026-05-27): in-flight guard. The slide-to-confirm
    // widget already prevents double-fire via its internal `_confirmed`
    // flag, but defense-in-depth on the highest-stakes financial commit
    // is cheap. If a future surface drives this method without the
    // slider (deep link, programmatic call, test) we still won't
    // double-debit.
    if (_isLoading) return;

    if (_amount <= 0) {
      setState(() => _error = 'Please enter a valid amount');
      return;
    }

    if (_isSendMode && !_hasSufficientFunds) {
      setState(() => _error = 'Insufficient balance');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isSendMode) {
        await _service.sendFunds(
          widget.friendshipId,
          _amount,
          _referenceController.text.isNotEmpty
              ? _referenceController.text
              : null,
          token,
        );
      } else {
        await _service.requestFunds(
          widget.friendshipId,
          _amount,
          _referenceController.text.isNotEmpty
              ? _referenceController.text
              : null,
          token,
        );
      }

      setState(() {
        _isSuccess = true;
        _isLoading = false;
      });

      // Auto-close after success animation
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _isSuccess ? _buildSuccessView(colors) : _buildFormView(colors),
    );
  }

  Widget _buildSuccessView(AzamanColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 40),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.success.withValues(alpha: 0.15),
                ),
                child: Icon(
                  Icons.check_circle_outline,
                  size: 40,
                  color: colors.success,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        Text(
          _isSendMode ? 'Funds Sent!' : 'Request Sent!',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isSendMode
              ? '\$${_amount.toStringAsFixed(2)} sent to ${widget.friendUsername}'
              : 'Requested \$${_amount.toStringAsFixed(2)} from ${widget.friendUsername}',
          style: TextStyle(color: colors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildFormView(AzamanColors colors) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            'Transfer to ${widget.friendUsername}',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Send / Request toggle
          Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _buildToggleTab('Send', _isSendMode, colors, () {
                  setState(() => _isSendMode = true);
                }),
                _buildToggleTab('Request', !_isSendMode, colors, () {
                  setState(() => _isSendMode = false);
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Amount input
          //
          // Internal transfers debit the sender's availableBalance, which is
          // the platform's cash ledger denominated in USDC (1:1 with USD).
          // The earlier label said "AZM" — leftover from the pre-Phase D-3
          // architecture where AZM and USDC were conflated. Phase D-3 split
          // them: AZM is a separate loyalty-point ledger, never debited or
          // credited through user-to-user transfers.
          Text(
            'Amount (USD)',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(
                color: colors.textTertiary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 20),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          // Balance display (for send mode)
          if (_isSendMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Available: ',
                    style: TextStyle(color: colors.textTertiary, fontSize: 13),
                  ),
                  Text(
                    '\$${_userBalance.toStringAsFixed(2)} USDC',
                    style: TextStyle(
                      color: _hasSufficientFunds
                          ? colors.success
                          : colors.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // Insufficient funds warning
          if (_isSendMode && _amount > 0 && !_hasSufficientFunds)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Insufficient balance',
                      style: TextStyle(color: colors.danger, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // Navigate to deposit screen
                      Navigator.pushNamed(context, '/deposit');
                    },
                    child: Text(
                      'Deposit',
                      style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Reference field
          Text(
            'Reference (optional)',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _referenceController,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            maxLength: 100,
            decoration: InputDecoration(
              hintText: 'What\'s this for?',
              hintStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              counterStyle: TextStyle(color: colors.textTertiary),
            ),
          ),
          const SizedBox(height: 20),

          // Error message
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: colors.danger, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),

          // Slide to confirm
          SlideToConfirm(
            key: _slideKey,
            text: _isSendMode ? 'Slide to send' : 'Slide to request',
            backgroundColor: colors.card,
            thumbColor: _isSendMode ? colors.success : colors.accent,
            onConfirmed: () {
              // Phase H3 — biometric pre-gate. The send-funds flow is a
              // direct debit on the sender's availableBalance, so it gets
              // the same gate as withdrawal/savings. Request-funds is a
              // signed intent that mints no transaction, but we still gate
              // it for symmetry — a malicious holder of an unlocked phone
              // could spam friends with bogus requests otherwise.
              AzamanBiometricGate.runSync(
                context,
                _executeTransfer,
                reason: _isSendMode
                    ? 'Authenticate to send funds'
                    : 'Authenticate to send request',
                onCancelled: () => _slideKey.currentState?.reset(),
              );
            },
            isLoading: _isLoading,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildToggleTab(
    String label,
    bool isActive,
    AzamanColors colors,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive
                  ? (colors.isDark ? Colors.black : Colors.white)
                  : colors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

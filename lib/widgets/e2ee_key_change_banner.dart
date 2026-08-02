// =============================================================================
// AZAMAN — E2EE Key Change Banner
//
// Shown in chat when a peer's encryption key has changed.
// Reference: WhatsApp's "Security code changed" system message banner.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class E2eeKeyChangeBanner extends StatelessWidget {
  final String peerName;
  final VoidCallback onDismiss;
  final VoidCallback onVerify;

  const E2eeKeyChangeBanner({
    super.key,
    required this.peerName,
    required this.onDismiss,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_reset, color: Color(0xFFFF9800), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$peerName\'s security code changed',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF5D4037),
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: onVerify,
                  child: const Text(
                    'Tap to verify',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFF9800),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF9E9E9E)),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.2);
  }
}

// lib/widgets/peer_transfer_card.dart
// =============================================================================
// PEER TRANSFER CARD — animated money-card rendering for friend-to-friend
// USDC transfers in chat (TRANSFER_SENT / TRANSFER_COMPLETED / TRANSFER_
// DECLINED / TRANSFER_REQUEST). Replaces the old plain-text "Sent 12.00 USDC"
// bubble with a proper card: gradient face, big amount, direction, status.
//
// Skins: `skin` picks the gradient. Default skin (null / 'classic') uses the
// Azaman brand gradient. Additional skins are purchasable in the Azaman
// Store and equipped per-user (metadata.cardSkin) — this widget just renders
// whatever skin id it's given, so the store/equip layer is a separate,
// additive piece of work built on top of this.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:azaman/models/chat_message.dart';

class CardSkinDef {
  final String id;
  final String label;
  final List<Color> colors;
  final Color textColor;
  const CardSkinDef(this.id, this.label, this.colors, {this.textColor = Colors.white});
}

/// Built-in skin catalog. Kept here (not fetched) so the card always renders
/// instantly even offline — the Store just writes a skin `id` onto the
/// user's profile / message metadata, this map resolves it to pixels.
const Map<String, CardSkinDef> kCardSkins = {
  'classic':  CardSkinDef('classic', 'Classic', [Color(0xFF4834DF), Color(0xFF6C5CE7)]),
  'gold':     CardSkinDef('gold', 'Gold', [Color(0xFFD4AF37), Color(0xFFF0B90B)], textColor: Color(0xFF1A1400)),
  'midnight': CardSkinDef('midnight', 'Midnight', [Color(0xFF0F0F1A), Color(0xFF23233B)]),
  'emerald':  CardSkinDef('emerald', 'Emerald', [Color(0xFF00B894), Color(0xFF00CEC9)]),
  'sunset':   CardSkinDef('sunset', 'Sunset', [Color(0xFFFF6B6B), Color(0xFFEE5A24)]),
};

CardSkinDef resolveSkin(String? id) => kCardSkins[id] ?? kCardSkins['classic']!;

class PeerTransferCard extends StatelessWidget {
  const PeerTransferCard({
    super.key,
    required this.message,
    required this.isMe,
    this.onTapRequest,
  });

  final ChatMessage message;
  final bool isMe;
  final VoidCallback? onTapRequest;

  @override
  Widget build(BuildContext context) {
    final meta = message.metadata ?? const {};
    final status = (meta['status'] ?? 'COMPLETED').toString().toUpperCase();
    final skin = resolveSkin(meta['cardSkin']?.toString());
    final amount = message.amount ?? 0.0;
    final currency = message.currency ?? 'USDC';
    final isRequest = message.kind == MessageKind.transferRequest;
    final isDeclined = status == 'DECLINED';

    final headline = isRequest
        ? (isMe ? 'You requested' : '${message.senderUsername ?? 'They'} requested')
        : (isMe ? 'You sent' : '${message.senderUsername ?? 'They'} sent');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      width: 240,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isRequest ? onTapRequest : null,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDeclined
                    ? [Colors.grey.shade600, Colors.grey.shade800]
                    : skin.colors,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDeclined ? Colors.black : skin.colors.last).withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isDeclined
                          ? Icons.close_rounded
                          : (isRequest ? Icons.request_page_rounded : Icons.arrow_upward_rounded),
                      color: skin.textColor.withValues(alpha: 0.85),
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isDeclined ? 'Transfer declined' : headline,
                      style: TextStyle(
                        color: skin.textColor.withValues(alpha: 0.85),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      amount.toStringAsFixed(2),
                      style: TextStyle(
                        color: skin.textColor,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currency,
                      style: TextStyle(
                        color: skin.textColor.withValues(alpha: 0.75),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (isRequest && !isMe) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text('Tap to respond',
                        style: TextStyle(color: skin.textColor, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    )
        // Entrance animation — subtle pop + fade, feels like a card being
        // dealt rather than a text bubble just appearing.
        .animate()
        .fadeIn(duration: 260.ms, curve: Curves.easeOut)
        .scale(begin: const Offset(0.88, 0.88), end: const Offset(1, 1), duration: 320.ms, curve: Curves.easeOutBack);
  }
}

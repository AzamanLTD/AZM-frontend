// =============================================================================
// QR PROFILE POPUP — real scannable identity QR
//
// PR-B of the Home/Settings refresh (spec §1.4). The drawer's profile hero
// carries a small live QR preview beside the identity row; tapping it opens
// this scan-ready popup. Both sizes render a REAL QrImageView (qr_flutter)
// with the payload contract `azaman://user/$username` — the exact payload
// qr_scanner_screen.dart parses (azaman://user/{username} → friends search
// → username match → friend request), so a scan of the popup performs a
// genuine add-friend flow.
//
// The centred Azaman logo over a light backing requires elevated error
// correction: the QR is encoded at QrErrorCorrectLevel.H so the logo
// overlap stays safely decodable (verified pattern: elevated ECC + centred
// logo ≤ 20% of the code area).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Payload builder shared by the thumbnail and the popup so both always
/// encode the same contract string for a given username.
String qrProfilePayload(String username) => 'azaman://user/$username';

/// Small scannable preview (used inside the drawer hero beside the
/// identity row). A real QR — not a decorative glyph — on a light backing.
class QrProfileThumbnail extends StatelessWidget {
  final String username;
  final double size;

  const QrProfileThumbnail({super.key, required this.username, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.07),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: QrImageView(
        data: qrProfilePayload(username),
        version: QrVersions.auto,
        padding: EdgeInsets.zero,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF141416),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF141416),
        ),
        errorCorrectionLevel: QrErrorCorrectLevel.H,
        embeddedImage: const AssetImage('assets/images/azaman_logo.png'),
        embeddedImageStyle: QrEmbeddedImageStyle(
          size: Size.square(size * 0.22),
        ),
      ),
    );
  }
}

/// The scan-ready popup content: a large QR with the centred Azaman logo
/// mark over a light backing, the @username below, and the payload hint.
/// Shown via [showQrProfilePopup].
class QrProfilePopup extends StatelessWidget {
  final String username;

  const QrProfilePopup({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF141416);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Light backing card holding the code — dark ink on near-white so
        // every scanner reads it regardless of app theme.
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: QrImageView(
            data: qrProfilePayload(username),
            version: QrVersions.auto,
            size: 220,
            gapless: true,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF141416),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF141416),
            ),
            errorCorrectionLevel: QrErrorCorrectLevel.H,
            embeddedImage: const AssetImage('assets/images/azaman_logo.png'),
            embeddedImageStyle: const QrEmbeddedImageStyle(
              size: Size.square(48),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '@$username',
          style: TextStyle(
            color: fg,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Scan to add me on Azaman',
          style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 13),
        ),
        const SizedBox(height: 22),
        // Close affordance for users who miss the barrier tap.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 18, color: fg.withValues(alpha: 0.7)),
            label: Text(
              'Close',
              style: TextStyle(color: fg.withValues(alpha: 0.8)),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: fg.withValues(alpha: 0.25)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens the QR popup as a dialog over the drawer. The dialog is a pure
/// overlay: dismissing it pops ONLY the dialog, leaving the drawer (and
/// its scroll position) exactly as it was.
Future<void> showQrProfilePopup(BuildContext context, String username) {
  HapticFeedback.lightImpact();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(dialogContext).brightness == Brightness.dark
              ? const Color(0xFF1C1C22)
              : const Color(0xFFF6F6F8),
          borderRadius: BorderRadius.circular(28),
        ),
        child: QrProfilePopup(username: username),
      ),
    ),
  );
}

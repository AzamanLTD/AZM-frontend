// =============================================================================
// AZAMAN — Incoming Call Overlay
//
// Shows a full-screen overlay when a call arrives while the app is open.
// Listens to the WebRTC service for incoming calls and navigates to the
// CallScreen with the right parameters.
//
// Reference: WhatsApp incoming call full-screen, Telegram
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/webrtc_service.dart';
import 'package:azaman/screens/call/call_screen.dart';

class IncomingCallOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const IncomingCallOverlay({super.key, required this.child});

  @override
  ConsumerState<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> {
  bool _navigatedToCall = false;

  @override
  void initState() {
    super.initState();
    final webrtc = ref.read(webrtcServiceProvider);

    webrtc.activeCall.listen((call) {
      if (call != null && call.state == CallState.incoming && !_navigatedToCall) {
        _navigatedToCall = true;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              peerId: call.callerId,
              peerName: call.callerName,
              peerAvatar: call.callerAvatar,
              isVideoCall: call.type == 'video',
              isCaller: false,
            ),
          ),
        ).then((_) {
          _navigatedToCall = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// =============================================================================
// AZAMAN — Call Screen (Voice/Video)
//
// WhatsApp-inspired call UI with:
//   - Pulsing avatar rings during ringing
//   - Full-screen video for video calls
//   - Call controls (mute, speaker, video toggle, end call)
//   - Call duration timer
//   - Call state transitions (calling → connected → ended)
//
// Reference: WhatsApp, Telegram, Cash App call screens
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/webrtc_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:azaman/services/socket_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

class CallScreen extends ConsumerStatefulWidget {
  final int peerId;
  final String peerName;
  final String? peerAvatar;
  final bool isVideoCall;
  final bool isCaller; // true = outgoing, false = incoming

  const CallScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
    this.isVideoCall = false,
    this.isCaller = true,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _ringController;
  late final WebRTCService _webrtc;
  CallState _callState = CallState.idle;
  Duration _callDuration = Duration.zero;
  bool _audioEnabled = true;
  bool _videoEnabled = false;
  bool _speakerEnabled = false;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _webrtc = ref.read(webrtcServiceProvider);
    _webrtc.setSocket(ref.read(socketServiceProvider));

    _webrtc.callState.listen((state) {
      if (mounted) {
        setState(() => _callState = state);
        if (state == CallState.connected) {
          _startDurationTimer();
        } else if (state == CallState.ended ||
            state == CallState.rejected ||
            state == CallState.failed ||
            state == CallState.missed) {
          _durationTimer?.cancel();
          _endCallAfterDelay();
        }
      }
    });

    _webrtc.activeCall.listen((call) {
      if (mounted && call != null) {
        setState(() {
          _callDuration = call.duration;
          _audioEnabled = call.audioEnabled;
          _videoEnabled = call.videoEnabled;
          _speakerEnabled = call.speakerEnabled;
        });
      }
    });

    if (widget.isCaller) {
      _startCall();
    }
  }

  void _startCall() async {
    await _webrtc.startCall(
      calleeId: widget.peerId,
      calleeName: widget.peerName,
      calleeAvatar: widget.peerAvatar,
      type: widget.isVideoCall ? 'video' : 'voice',
    );
  }

  void _endCall() {
    _webrtc.endCall();
    _durationTimer?.cancel();
  }

  void _endCallAfterDelay() {
    Timer(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDuration += const Duration(seconds: 1));
      }
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _stateLabel() {
    switch (_callState) {
      case CallState.ringing:
        return widget.isCaller ? 'Calling…' : 'Incoming call';
      case CallState.incoming:
        return 'Incoming call';
      case CallState.connecting:
        return 'Connecting…';
      case CallState.connected:
        return _formatDuration(_callDuration);
      case CallState.reconnecting:
        return 'Reconnecting…';
      case CallState.ended:
        return 'Call ended';
      case CallState.rejected:
        return 'Call rejected';
      case CallState.missed:
        return 'Missed call';
      case CallState.failed:
        return 'Call failed';
      default:
        return 'Calling…';
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _ringController.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF1A1A2E);
    final isConnected = _callState == CallState.connected;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top: name + status
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  Text(
                    widget.peerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _stateLabel(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Center: Avatar/Video
            Expanded(
              child: Center(
                child: widget.isVideoCall && isConnected
                    ? _VideoCallView(webrtc: _webrtc)
                    : _AvatarRings(
                        avatar: widget.peerAvatar,
                        name: widget.peerName,
                        pulseAnimation: _pulseController,
                        ringAnimation: _ringController,
                        isRinging: _callState == CallState.ringing ||
                            _callState == CallState.incoming,
                      ),
              ),
            ),

            // Bottom: Controls
            Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: _CallControls(
                state: _callState,
                audioEnabled: _audioEnabled,
                videoEnabled: _videoEnabled,
                speakerEnabled: _speakerEnabled,
                isVideoCall: widget.isVideoCall,
                isCaller: widget.isCaller,
                onEndCall: _endCall,
                onToggleMute: () {
                  _webrtc.toggleMute();
                  setState(() => _audioEnabled = !_audioEnabled);
                },
                onToggleSpeaker: () {
                  _webrtc.toggleSpeaker();
                  setState(() => _speakerEnabled = !_speakerEnabled);
                },
                onToggleVideo: () {
                  _webrtc.toggleVideo();
                  setState(() => _videoEnabled = !_videoEnabled);
                },
                onAccept: () => _webrtc.acceptCall(),
                onReject: () => _webrtc.rejectCall(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar with pulsing rings ───────────────────────────────────────────────
class _AvatarRings extends StatelessWidget {
  final String? avatar;
  final String name;
  final Animation<double> pulseAnimation;
  final Animation<double> ringAnimation;
  final bool isRinging;

  const _AvatarRings({
    required this.avatar,
    required this.name,
    required this.pulseAnimation,
    required this.ringAnimation,
    this.isRinging = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isRinging) ...List.generate(3, (i) {
            return AnimatedBuilder(
              animation: ringAnimation,
              builder: (context, child) {
                final progress = (ringAnimation.value + i * 0.33) % 1.0;
                final size = 120.0 + progress * 100;
                final opacity = (1 - progress) * 0.4;
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: opacity),
                      width: 2,
                    ),
                  ),
                );
              },
            );
          }),
          AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, child) {
              final scale = 1.0 + pulseAnimation.value * 0.05;
              return Transform.scale(
                scale: isRinging ? scale : 1.0,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: avatar != null
                      ? ClipOval(child: AzamanNetworkImage(imageUrl: avatar!, fit: BoxFit.cover))
                      : Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Video call view ─────────────────────────────────────────────────────────
class _VideoCallView extends StatelessWidget {
  final WebRTCService webrtc;

  const _VideoCallView({required this.webrtc});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Remote video
        StreamBuilder<MediaStream>(
          stream: webrtc.remoteStream,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final renderer = RTCVideoRenderer();
              renderer.srcObject = snapshot.data;
              return RTCVideoView(
                renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              );
            }
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          },
        ),
        // Local video PiP
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            width: 120,
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: const Center(
                child: Text('You',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Call controls ───────────────────────────────────────────────────────────
class _CallControls extends StatelessWidget {
  final CallState state;
  final bool audioEnabled;
  final bool videoEnabled;
  final bool speakerEnabled;
  final bool isVideoCall;
  final bool isCaller;
  final VoidCallback onEndCall;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleVideo;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _CallControls({
    required this.state,
    required this.audioEnabled,
    required this.videoEnabled,
    required this.speakerEnabled,
    required this.isVideoCall,
    required this.isCaller,
    required this.onEndCall,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onToggleVideo,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    // Incoming call — accept/reject
    if (state == CallState.incoming && !isCaller) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: Icons.close_rounded,
            label: 'Reject',
            color: Colors.red,
            onPressed: onReject,
          ),
          _ControlButton(
            icon: Icons.call_rounded,
            label: 'Accept',
            color: const Color(0xFF2ECC71),
            onPressed: onAccept,
            size: 72,
          ),
        ],
      );
    }

    // Active or outgoing call
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: audioEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
          label: audioEnabled ? 'Mute' : 'Unmute',
          color: Colors.white,
          active: !audioEnabled,
          onPressed: onToggleMute,
        ),
        if (isVideoCall)
          _ControlButton(
            icon: videoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: videoEnabled ? 'Video On' : 'Video Off',
            color: Colors.white,
            active: !videoEnabled,
            onPressed: onToggleVideo,
          ),
        _ControlButton(
          icon: speakerEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          label: 'Speaker',
          color: Colors.white,
          active: speakerEnabled,
          onPressed: onToggleSpeaker,
        ),
        _ControlButton(
          icon: Icons.call_end_rounded,
          label: 'End',
          color: Colors.red,
          onPressed: onEndCall,
          size: 72,
        ),
      ],
    );
  }
}

// ── Single control button ───────────────────────────────────────────────────
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final double size;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    this.active = false,
    this.size = 60,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.1),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: IconButton(
            icon: Icon(icon, color: active ? Colors.black : color, size: size * 0.45),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
        ),
      ],
    );
  }
}

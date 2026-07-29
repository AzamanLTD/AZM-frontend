// =============================================================================
// AZAMAN — WebRTC Service (Voice/Video Calls)
//
// Architecture:
//   1. Caller creates RTCPeerConnection, generates offer
//   2. Offer sent via Socket.IO signaling to callee
//   3. Callee accepts, generates answer, sends back
//   4. ICE candidates exchanged via Socket.IO
//   5. Media stream (audio/video) negotiated
//   6. Call established — media flows P2P (TURN server fallback)
//
// Signaling events (all via Socket.IO):
//   Outgoing: webrtc_call_initiate, webrtc_call_offer, webrtc_call_answer,
//             webrtc_call_reject, webrtc_call_end, webrtc_ice_candidate,
//             webrtc_media_state, webrtc_call_metrics
//   Incoming: webrtc_incoming_call, webrtc_call_offer, webrtc_call_answer,
//             webrtc_call_rejected, webrtc_ice_candidate, webrtc_call_ended,
//             webrtc_call_busy, webrtc_media_state
//
// Reference: WhatsApp (P2P media + relay signaling), Telegram (E2E calls)
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/socket_service.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final webrtcServiceProvider = Provider<WebRTCService>((ref) {
  return WebRTCService();
});

// ---------------------------------------------------------------------------
// Call State Enum
// ---------------------------------------------------------------------------
enum CallState {
  idle,           // No active call
  ringing,         // Outgoing call — waiting for callee to answer
  incoming,        // Incoming call — waiting for user to accept/reject
  connecting,      // SDP negotiation in progress
  connected,       // Call established, media flowing
  reconnecting,    // ICE restart in progress
  ended,           // Call ended normally
  rejected,        // Call was rejected by the other party
  missed,          // Incoming call was not answered
  failed,          // Call failed (network error, timeout, etc.)
}

// ---------------------------------------------------------------------------
// Call Data Model
// ---------------------------------------------------------------------------
class ActiveCall {
  final String callId;
  final int callerId;
  final int calleeId;
  final String callerName;
  final String? callerAvatar;
  final String type; // 'voice' | 'video'
  final bool isCaller; // true if this user initiated the call
  CallState state;
  Duration duration;
  bool audioEnabled;
  bool videoEnabled;
  bool speakerEnabled;

  ActiveCall({
    required this.callId,
    required this.callerId,
    required this.calleeId,
    required this.callerName,
    this.callerAvatar,
    required this.type,
    required this.isCaller,
    this.state = CallState.idle,
    this.duration = Duration.zero,
    this.audioEnabled = true,
    this.videoEnabled = false,
    this.speakerEnabled = false,
  });
}

// ---------------------------------------------------------------------------
// WebRTC Service
// ---------------------------------------------------------------------------
class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _stateController = StreamController<CallState>.broadcast();
  final _callController = StreamController<ActiveCall?>.broadcast();

  Stream<MediaStream> get remoteStream => _remoteStreamController.stream;
  Stream<CallState> get callState => _stateController.stream;
  Stream<ActiveCall?> get activeCall => _callController.stream;

  ActiveCall? currentCall;
  Timer? _durationTimer;
  Timer? _ringingTimeout;
  SocketService? _socket;

  // STUN/TURN servers — public STUN for now, add TURN for production
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      // TURN servers will be configured per-environment
      // {'urls': 'turn:turn.example.com:3478', 'username': '...', 'credential': '...'},
    ],
    'iceTransportPolicy': 'all',
  };

  /// Initialize WebRTC — call once at app startup
  Future<void> initialize() async {
    // WebRTC initialization is automatic in flutter_webrtc ^0.12
  }

  /// Set socket reference for signaling
  void setSocket(SocketService socket) {
    _socket = socket;
    _registerSocketListeners();
  }

  /// Register all incoming socket event listeners
  void _registerSocketListeners() {
    final s = _socket?.socket;
    if (s == null) return;

    // Incoming call notification
    s.on('webrtc_incoming_call', (data) {
      _handleIncomingCall(data);
    });

    // Call offer (SDP) from the other party
    s.on('webrtc_call_offer', (data) {
      _handleCallOffer(data);
    });

    // Call answer (SDP) — caller receives the callee's answer
    s.on('webrtc_call_answer', (data) {
      _handleCallAnswer(data);
    });

    // Call rejected
    s.on('webrtc_call_rejected', (data) {
      _updateCallState(CallState.rejected);
      _cleanup();
      _ringingTimeout?.cancel();
    });

    // Call ended by the other party
    s.on('webrtc_call_ended', (data) {
      _updateCallState(CallState.ended);
      _cleanup();
      _ringingTimeout?.cancel();
    });

    // Call busy
    s.on('webrtc_call_busy', (data) {
      _updateCallState(CallState.failed);
      _cleanup();
    });

    // ICE candidate from the other party
    s.on('webrtc_ice_candidate', (data) {
      _handleIceCandidate(data);
    });

    // Media state change (mute/unmute/video toggle)
    s.on('webrtc_media_state', (data) {
      if (currentCall != null && data['from'] != null) {
        // Update remote media state in UI
        _callController.add(currentCall);
      }
    });
  }

  /// ── START A CALL ──────────────────────────────────────────────────────
  Future<void> startCall({
    required int calleeId,
    required String calleeName,
    String? calleeAvatar,
    required String type, // 'voice' | 'video'
  }) async {
    if (currentCall != null) return; // Already in a call

    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    currentCall = ActiveCall(
      callId: callId,
      callerId: _socket?.userIdInt ?? 0,
      calleeId: calleeId,
      callerName: calleeName,
      callerAvatar: calleeAvatar,
      type: type,
      isCaller: true,
      state: CallState.ringing,
      videoEnabled: type == 'video',
    );

    _callController.add(currentCall);
    _updateCallState(CallState.ringing);

    // Initiate call via socket signaling
    _socket?.socket?.emit('webrtc_call_initiate', {
      'calleeId': calleeId,
      'type': type,
    });

    // Set ringing timeout (30s)
    _ringingTimeout = Timer(const Duration(seconds: 30), () {
      if (currentCall?.state == CallState.ringing) {
        endCall();
        _updateCallState(CallState.failed);
      }
    });
  }

  /// ── HANDLE INCOMING CALL ───────────────────────────────────────────────
  void _handleIncomingCall(Map<String, dynamic> data) {
    if (currentCall != null) {
      // Already in a call — auto-reject
      _socket?.socket?.emit('webrtc_call_reject', {
        'to': data['callerId'],
        'callId': data['callId'],
        'reason': 'busy',
      });
      return;
    }

    currentCall = ActiveCall(
      callId: data['callId'] ?? '',
      callerId: data['callerId'] ?? 0,
      calleeId: _socket?.userIdInt ?? 0,
      callerName: data['callerName'] ?? 'Unknown',
      callerAvatar: data['callerAvatar'],
      type: data['type'] ?? 'voice',
      isCaller: false,
      state: CallState.incoming,
    );

    _callController.add(currentCall);
    _updateCallState(CallState.incoming);
  }

  /// ── ACCEPT INCOMING CALL ──────────────────────────────────────────────
  Future<void> acceptCall() async {
    if (currentCall == null) return;

    _updateCallState(CallState.connecting);

    // Get user media
    await _getUserMedia(isVideo: currentCall!.type == 'video');

    // Create peer connection
    _peerConnection = await createPeerConnection(_iceServers);

    // Add local tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // Handle remote stream
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream!);
      }
    };

    // ICE candidate handling
    _peerConnection!.onIceCandidate = (candidate) {
      _socket?.socket?.emit('webrtc_ice_candidate', {
        'to': currentCall!.callerId,
        'callId': currentCall!.callId,
        'candidate': candidate.toMap(),
      });
    };

    // ICE connection state
    _peerConnection!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        _updateCallState(CallState.connected);
        _startDurationTimer();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _updateCallState(CallState.failed);
        endCall();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _updateCallState(CallState.reconnecting);
      }
    };
  }

  /// ── HANDLE CALL OFFER (callee receives SDP offer) ─────────────────────
  Future<void> _handleCallOffer(Map<String, dynamic> data) async {
    if (currentCall == null || _peerConnection == null) return;

    final sdp = data['sdp'];
    if (sdp == null) return;

    // Set remote description (the offer)
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'] ?? '', sdp['type'] ?? 'offer'),
    );

    // Create answer
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    // Send answer back to caller
    _socket?.socket?.emit('webrtc_call_answer', {
      'to': data['from'],
      'callId': currentCall!.callId,
      'sdp': answer.toMap(),
    });
  }

  /// ── HANDLE CALL ANSWER (caller receives SDP answer) ───────────────────
  Future<void> _handleCallAnswer(Map<String, dynamic> data) async {
    if (currentCall == null || _peerConnection == null) return;

    final sdp = data['sdp'];
    if (sdp == null) return;

    _ringingTimeout?.cancel();

    // Need to get user media + create peer connection if not done yet
    if (_localStream == null) {
      await _getUserMedia(isVideo: currentCall!.type == 'video');
      _peerConnection = await createPeerConnection(_iceServers);

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      }

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _remoteStreamController.add(_remoteStream!);
        }
      };

      _peerConnection!.onIceCandidate = (candidate) {
        _socket?.socket?.emit('webrtc_ice_candidate', {
          'to': currentCall!.calleeId,
          'callId': currentCall!.callId,
          'candidate': candidate.toMap(),
        });
      };

      _peerConnection!.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          _updateCallState(CallState.connected);
          _startDurationTimer();
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _updateCallState(CallState.failed);
          endCall();
        }
      };
    }

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'] ?? '', sdp['type'] ?? 'answer'),
    );
  }

  /// ── HANDLE ICE CANDIDATE ──────────────────────────────────────────────
  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;

    final candidateData = data['candidate'];
    if (candidateData == null) return;

    final candidate = RTCIceCandidate(
      candidateData['candidate'] ?? '',
      candidateData['sdpMid'] ?? '',
      candidateData['sdpMLineIndex'] ?? 0,
    );

    await _peerConnection!.addCandidate(candidate);
  }

  /// ── SEND OFFER (caller side — after callee accepts) ───────────────────
  Future<void> _sendOffer() async {
    if (currentCall == null || _peerConnection == null) return;

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _socket?.socket?.emit('webrtc_call_offer', {
      'to': currentCall!.calleeId,
      'callId': currentCall!.callId,
      'sdp': offer.toMap(),
    });
  }

  /// ── REJECT INCOMING CALL ──────────────────────────────────────────────
  void rejectCall() {
    if (currentCall == null) return;

    _socket?.socket?.emit('webrtc_call_reject', {
      'to': currentCall!.callerId,
      'callId': currentCall!.callId,
      'reason': 'declined',
    });

    _updateCallState(CallState.rejected);
    _cleanup();
  }

  /// ── END CALL ──────────────────────────────────────────────────────────
  void endCall() {
    if (currentCall == null) return;

    final otherId = currentCall!.isCaller
        ? currentCall!.calleeId
        : currentCall!.callerId;

    _socket?.socket?.emit('webrtc_call_end', {
      'to': otherId,
      'callId': currentCall!.callId,
    });

    _updateCallState(CallState.ended);
    _cleanup();
  }

  /// ── TOGGLE MUTE ───────────────────────────────────────────────────────
  void toggleMute() {
    if (_localStream == null || currentCall == null) return;

    currentCall!.audioEnabled = !currentCall!.audioEnabled;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = currentCall!.audioEnabled;
    }

    _socket?.socket?.emit('webrtc_media_state', {
      'to': currentCall!.isCaller ? currentCall!.calleeId : currentCall!.callerId,
      'callId': currentCall!.callId,
      'audioEnabled': currentCall!.audioEnabled,
      'videoEnabled': currentCall!.videoEnabled,
    });

    _callController.add(currentCall);
  }

  /// ── TOGGLE SPEAKER ────────────────────────────────────────────────────
  void toggleSpeaker() {
    if (currentCall == null) return;
    currentCall!.speakerEnabled = !currentCall!.speakerEnabled;
    // flutter_webrtc handles speakerphone via audio output selection
    _callController.add(currentCall);
  }

  /// ── TOGGLE VIDEO ──────────────────────────────────────────────────────
  Future<void> toggleVideo() async {
    if (currentCall == null) return;

    currentCall!.videoEnabled = !currentCall!.videoEnabled;

    if (currentCall!.videoEnabled && _localStream != null) {
      // Add video track
      final videoTrack = _localStream!.getVideoTracks();
      for (final track in videoTrack) {
        track.enabled = true;
      }
    } else if (_localStream != null) {
      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = false;
      }
    }

    _socket?.socket?.emit('webrtc_media_state', {
      'to': currentCall!.isCaller ? currentCall!.calleeId : currentCall!.callerId,
      'callId': currentCall!.callId,
      'audioEnabled': currentCall!.audioEnabled,
      'videoEnabled': currentCall!.videoEnabled,
    });

    _callController.add(currentCall);
  }

  /// ── GET USER MEDIA ────────────────────────────────────────────────────
  Future<void> _getUserMedia({required bool isVideo}) async {
    final constraints = {
      'audio': true,
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'min': 320, 'ideal': 640, 'max': 1280},
              'height': {'min': 240, 'ideal': 480, 'max': 720},
            }
          : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);

    if (!isVideo) {
      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = false;
      }
    }
  }

  /// ── CREATE PEER CONNECTION (caller side) ──────────────────────────────
  Future<void> _createCallerPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream!);
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      _socket?.socket?.emit('webrtc_ice_candidate', {
        'to': currentCall!.calleeId,
        'callId': currentCall!.callId,
        'candidate': candidate.toMap(),
      });
    };

    _peerConnection!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        _updateCallState(CallState.connected);
        _startDurationTimer();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _updateCallState(CallState.failed);
        endCall();
      }
    };
  }

  /// ── START DURATION TIMER ──────────────────────────────────────────────
  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (currentCall != null) {
        currentCall!.duration += const Duration(seconds: 1);
        _callController.add(currentCall);
      }
    });
  }

  /// ── UPDATE CALL STATE ─────────────────────────────────────────────────
  void _updateCallState(CallState state) {
    if (currentCall != null) {
      currentCall!.state = state;
      _stateController.add(state);
      _callController.add(currentCall);
    }
  }

  /// ── CLEANUP ───────────────────────────────────────────────────────────
  void _cleanup() {
    _durationTimer?.cancel();
    _ringingTimeout?.cancel();

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.stop();
      }
      _localStream!.dispose();
      _localStream = null;
    }

    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }

    _remoteStream = null;

    // Delay clearing currentCall so UI can show "call ended" state briefly
    Timer(const Duration(seconds: 2), () {
      currentCall = null;
      _callController.add(null);
    });
  }

  /// ── DISPOSE ───────────────────────────────────────────────────────────
  void dispose() {
    _cleanup();
    _remoteStreamController.close();
    _stateController.close();
    _callController.close();
  }
}

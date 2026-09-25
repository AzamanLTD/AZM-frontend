// =============================================================================
// AZAMAN — CONNECTIVITY BANNER  (Phase H4)
//
// Thin slide-down strip that appears at the top of every screen when the
// device loses network and stays until the radio reports a connection again.
// A quick green "Reconnected" flash plays for ~1.4s after recovery, then the
// banner slides back up.
//
// Usage
// -----
// Wrap the app's body once at the root (in `main.dart` MaterialApp.builder)
// so the banner overlays every route. The banner does NOT push content down
// — it sits inside a `SafeArea`-aware `Stack` overlay so screens can't
// accidentally re-layout under it (which would cause a noticeable jolt
// every time the user walked through a tunnel).
//
// Tied into the existing AzamanHaptics + theme vocabulary. No external
// dependencies beyond the connectivity stream itself.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/connectivity_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';


class AzamanConnectivityBanner extends ConsumerStatefulWidget {
  /// The actual app body. The banner is overlaid above it so the user's
  /// screens never reflow when connectivity flips.
  final Widget child;

  const AzamanConnectivityBanner({super.key, required this.child});

  @override
  ConsumerState<AzamanConnectivityBanner> createState() =>
      _AzamanConnectivityBannerState();
}

enum _BannerState { hidden, offline, reconnected }

class _AzamanConnectivityBannerState
    extends ConsumerState<AzamanConnectivityBanner> {
  _BannerState _state = _BannerState.hidden;
  bool? _lastKnownOnline;
  Timer? _reconnectFlashTimer;

  @override
  void dispose() {
    _reconnectFlashTimer?.cancel();
    super.dispose();
  }

  void _onConnectivityChange(bool online) {
    // First emission seeds _lastKnownOnline without firing a banner — we
    // don't want to ping the user with "Reconnected!" the moment the app
    // launches into a perfectly normal online state.
    if (_lastKnownOnline == null) {
      _lastKnownOnline = online;
      if (!online) {
        _state = _BannerState.offline;
      }
      return;
    }

    if (online == _lastKnownOnline) return;
    _lastKnownOnline = online;

    if (!online) {
      _reconnectFlashTimer?.cancel();
      _reconnectFlashTimer = null;
      AzamanHaptics.warn();
      _state = _BannerState.offline;
    } else {
      // We were offline; flash green for a beat, then hide.
      AzamanHaptics.confirm();
      _state = _BannerState.reconnected;
      _reconnectFlashTimer?.cancel();
      _reconnectFlashTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        setState(() => _state = _BannerState.hidden);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    // Drive the state machine off the connectivity stream.
    ref.listen<AsyncValue<bool>>(connectivityProvider, (_, next) {
      next.whenData((online) {
        // setState wraps every transition so the banner Slides as a single
        // animation tick, not as two separate frames.
        setState(() => _onConnectivityChange(online));
      });
    });

    return Stack(
      children: [
        widget.child,
        if (_state != _BannerState.hidden)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _BannerStrip(state: _state, colors: colors),
            ),
          ),
      ],
    );
  }
}

class _BannerStrip extends StatelessWidget {
  final _BannerState state;
  final AzamanColors colors;

  const _BannerStrip({required this.state, required this.colors});

  @override
  Widget build(BuildContext context) {
    final isOffline = state == _BannerState.offline;
    final bgColor = isOffline ? colors.danger : colors.success;
    final icon = isOffline
        ? Icons.cloud_outlined
        : Icons.cloud_outlined;
    final label = isOffline
        ? 'You are offline'
        : 'Reconnected';
    final subtitle = isOffline
        ? 'Showing your last loaded data. Some actions are paused.'
        : null;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      offset: Offset.zero,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: bgColor.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

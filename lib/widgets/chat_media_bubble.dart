// =============================================================================
// CHAT MEDIA BUBBLE — Phase UI-3 (2026-05-26)
//
// Stateless renderer that knows how to draw any of the five media kinds
// shipped with Phase UI-3:
//
//   • IMAGE     — full-width thumbnail, tap to open with `open_filex`.
//   • VIDEO     — 16:9 thumbnail with a play overlay; tap opens system player.
//   • DOCUMENT  — file row with icon, filename, size; tap opens system viewer.
//   • AUDIO     — playback row with play button + duration label + waveform
//                 (placeholder bars until a future PR wires `record` playback).
//   • LINK      — Open Graph preview card with title, description, hero image.
//
// Used by:
//   • Direct chat (personal_chat_interface.dart, friend_chat_screen.dart)
//   • Trade chat (chat_interface.dart) — same widget, same wire format.
//   • Ticket workspace (Phase UI-4) — drop-in.
//   • Media & Ledger Vault grids (Phase UI-5) — same models.
//
// Wire format (MEDIA_PAYLOAD object on a message):
//   {
//     "messageType": "IMAGE | VIDEO | AUDIO | DOCUMENT | LINK",
//     "mediaUrl":      "/uploads/chat/123/image/chat-...png",
//     "mediaMimeType": "image/png",
//     "mediaSize":     45821,
//     "mediaDuration": 12,                       // audio/video only
//     "mediaWaveformPeaks": [12, 34, 18, ...],   // audio only, 50 buckets
//     "linkPreview":   { url, title, description, image, favicon, siteName, status }
//   }
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/chat_media_service.dart';
import 'package:azaman/screens/chat/media_viewer_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';


/// All metadata needed to render a media bubble. Wraps the wire format so
/// callers don't have to remember which message field maps to which UI bit.
class ChatMediaPayload {
  final String type; // IMAGE | VIDEO | AUDIO | DOCUMENT | LINK
  final String? url;
  final String? mimeType;
  final int? size;
  final int? duration;
  final List<int>? waveformPeaks;
  final LinkPreview? linkPreview;
  final String? caption; // optional text content sent alongside media

  const ChatMediaPayload({
    required this.type,
    this.url,
    this.mimeType,
    this.size,
    this.duration,
    this.waveformPeaks,
    this.linkPreview,
    this.caption,
  });

  factory ChatMediaPayload.fromMessageJson(Map<String, dynamic> json) {
    final preview = json['linkPreview'];
    final waveform = json['mediaWaveformPeaks'];
    return ChatMediaPayload(
      type: (json['messageType'] ?? 'TEXT').toString().toUpperCase(),
      url: json['mediaUrl']?.toString(),
      mimeType: json['mediaMimeType']?.toString(),
      size: json['mediaSize'] is int ? json['mediaSize'] as int : null,
      duration: json['mediaDuration'] is int ? json['mediaDuration'] as int : null,
      waveformPeaks: waveform is List ? waveform.whereType<int>().toList() : null,
      linkPreview: preview is Map<String, dynamic>
          ? LinkPreview.fromJson(preview)
          : null,
      caption: json['content']?.toString(),
    );
  }

  bool get isMedia => const {
        'IMAGE',
        'VIDEO',
        'AUDIO',
        'DOCUMENT',
        'LINK',
      }.contains(type);
}

class ChatMediaBubble extends ConsumerWidget {
  final ChatMediaPayload payload;
  final bool isMe;

  const ChatMediaBubble({
    super.key,
    required this.payload,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    switch (payload.type) {
      case 'IMAGE':
        return _ImageBubble(payload: payload, colors: colors);
      case 'VIDEO':
        return _VideoBubble(payload: payload, colors: colors);
      case 'AUDIO':
        return _AudioBubble(payload: payload, colors: colors, isMe: isMe);
      case 'DOCUMENT':
        return _DocumentBubble(payload: payload, colors: colors);
      case 'LINK':
        return _LinkBubble(payload: payload, colors: colors);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _resolveMediaUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  // Server returns paths like "/uploads/chat/12/image/chat-x.png".
  // The backend's apiUrl ends in /api; strip it for static asset access.
  final apiBase = AppConfig.apiUrl;
  final origin = apiBase.endsWith('/api')
      ? apiBase.substring(0, apiBase.length - 4)
      : apiBase;
  return '$origin$url';
}

String _formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String _formatDuration(int? seconds) {
  if (seconds == null || seconds < 0) return '';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

Future<void> _openMediaViewer(BuildContext ctx, ChatMediaPayload p) async {
  final url = p.url;
  if (url == null) return;
  Navigator.of(ctx).push(
    MaterialPageRoute(
      builder: (_) => MediaViewerScreen(
        heroTag: 'media_${url.hashCode}',
        items: [
          MediaViewerItem(
            url: url,
            type: p.type,
            caption: p.caption,
          ),
        ],
        initialIndex: 0,
      ),
    ),
  );
}

Future<void> _openInSystemViewer(BuildContext ctx, ChatMediaPayload p) async {
  final url = p.url;
  if (url == null) return;
  final resolved = _resolveMediaUrl(url);
  try {
    // Download to tmp then open with system viewer for documents/videos. For
    // images we keep it simple and just open the URL; iOS/Android's default
    // browser handles inline preview cleanly.
    if (p.type == 'IMAGE') {
      await launchUrl(Uri.parse(resolved), mode: LaunchMode.externalApplication);
      return;
    }
    final res = await http.get(Uri.parse(resolved));
    if (res.statusCode != 200) {
      throw Exception('Download failed: ${res.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final filename = url.split('/').last;
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(res.bodyBytes);
    await OpenFilex.open(file.path);
  } catch (e) {
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('Could not open: $e')),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE
// ─────────────────────────────────────────────────────────────────────────────

class _ImageBubble extends StatelessWidget {
  final ChatMediaPayload payload;
  final AzamanColors colors;
  const _ImageBubble({required this.payload, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (payload.url == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _openMediaViewer(context, payload);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(imageUrl: 
          _resolveMediaUrl(payload.url!),
          fit: BoxFit.cover,
          width: 240,
          height: 240,
          errorWidget: (_, __, ___) => _ErrorTile(
            colors: colors,
            icon: Icons.image_outlined,
            label: 'Image unavailable',
          ),
          placeholder: (_, url) => _LoadingTile(colors: colors, height: 240),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIDEO
// ─────────────────────────────────────────────────────────────────────────────

class _VideoBubble extends StatelessWidget {
  final ChatMediaPayload payload;
  final AzamanColors colors;
  const _VideoBubble({required this.payload, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (payload.url == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _openMediaViewer(context, payload);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 260,
              height: 160,
              color: colors.card,
              child: const Icon(Icons.movie_outlined,
                  size: 40, color: Colors.white24),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_circle_outline,
                  color: Colors.white, size: 28),
            ),
            if (payload.duration != null)
              Positioned(
                right: 8,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(payload.duration),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUDIO  (Phase UI-POLISH 2026-05-26 — in-bubble inline playback)
//
// Stateful bubble that plays audio inline using `audioplayers`. Tap the
// circle to play/pause; the waveform bars colour-fill in proportion to
// the playback position; the duration label flips between elapsed and
// total time during playback. Globally, only one audio bubble plays at a
// time — opening another bubble (or a new screen with another bubble)
// stops the previous one via the shared `_AudioBubblePlayer` singleton.
// ─────────────────────────────────────────────────────────────────────────────

class _AudioBubble extends StatefulWidget {
  final ChatMediaPayload payload;
  final AzamanColors colors;
  final bool isMe;
  const _AudioBubble({
    required this.payload,
    required this.colors,
    required this.isMe,
  });

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> with WidgetsBindingObserver {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  bool _loading = false;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final declaredSec = widget.payload.duration;
    if (declaredSec != null && declaredSec > 0) {
      _duration = Duration(seconds: declaredSec);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing && _player != null) {
      _player!.pause();
      setState(() => _playing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _stateSub?.cancel();
    final p = _player;
    if (p != null) {
      _AudioBubblePlayerRegistry.instance.unregister(p);
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _ensurePlayer() async {
    if (_player != null) return;
    final p = AudioPlayer();
    _player = p;
    _AudioBubblePlayerRegistry.instance.register(p);

    _positionSub = p.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _stateSub = p.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state == PlayerState.playing;
        if (state == PlayerState.completed) {
          _position = Duration.zero;
          _playing = false;
        }
      });
    });

    final dur = await p.getDuration().catchError((_) => null);
    if (mounted && dur != null && dur != Duration.zero) {
      setState(() => _duration = dur);
    }
  }

  Future<void> _toggle() async {
    final url = widget.payload.url;
    if (url == null) return;
    HapticFeedback.lightImpact();
    await _ensurePlayer();
    final p = _player!;

    if (_playing) {
      await p.pause();
      return;
    }
    // Stop any other active audio bubbles before starting this one.
    _AudioBubblePlayerRegistry.instance.stopOthers(p);

    setState(() => _loading = true);
    try {
      // If we've already loaded once, the source is set; just resume.
      // Otherwise set it and play. audioplayers handles seeking after
      // setSourceUrl; we use UrlSource for remote audio.
      if (_position == Duration.zero) {
        await p.play(UrlSource(_resolveMediaUrl(url)));
      } else {
        await p.resume();
      }
      // Pull final duration if we still don't have it.
      if (_duration == null || _duration == Duration.zero) {
        final dur = await p.getDuration().catchError((_) => null);
        if (mounted && dur != null && dur != Duration.zero) {
          setState(() => _duration = dur);
        }
      }
    } catch (_) {
      // Fall back to the system viewer for codecs the package can't
      // handle (e.g. some HEIC-style audio variants).
      await _openInSystemViewer(context, widget.payload);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seek(double fraction) async {
    if (_duration == null || _duration == Duration.zero) return;
    HapticFeedback.selectionClick();
    final target =
        Duration(milliseconds: (_duration!.inMilliseconds * fraction).round());
    setState(() => _position = target);
    await _ensurePlayer();
    await _player!.seek(target);
  }

  void _cycleSpeed() {
    HapticFeedback.selectionClick();
    const speeds = [1.0, 1.5, 2.0];
    final next = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
    setState(() => _speed = next);
    if (_player != null) _player!.setPlaybackRate(next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isMe
        ? (widget.colors.isDark ? Colors.white : Colors.black87)
        : widget.colors.accent;
    final dur = _duration;
    final progress = (dur != null && dur.inMilliseconds > 0)
        ? (_position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final label = _playing || _position > Duration.zero
        ? _formatDurationFromMs(_position.inSeconds)
        : (widget.payload.duration != null
            ? _formatDurationFromMs(widget.payload.duration!)
            : '0:00');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: _loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(
                        _playing
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        color: accent,
                        size: 22,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box.globalToLocal(d.globalPosition);
                final width = box.size.width;
                if (width <= 0) return;
                _seek((local.dx / width).clamp(0.0, 1.0));
              },
              onHorizontalDragUpdate: (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box.globalToLocal(d.globalPosition);
                final width = box.size.width;
                if (width <= 0) return;
                _seek((local.dx / width).clamp(0.0, 1.0));
              },
              child: SizedBox(
                height: 28,
                child: _Waveform(
                  peaks: widget.payload.waveformPeaks,
                  color: accent,
                  progress: progress,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: accent.withValues(alpha: 0.85),
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (_playing || _position > Duration.zero) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _cycleSpeed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Text(
                  '${_speed}x',
                  style: TextStyle(
                    fontSize: 10,
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDurationFromMs(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Tracks every active `AudioPlayer` from a chat audio bubble so that
/// when the user starts a new bubble, every other one pauses. Mirrors
/// the WhatsApp / iMessage behaviour where only one voice note plays
/// at a time.
class _AudioBubblePlayerRegistry {
  _AudioBubblePlayerRegistry._();
  static final _AudioBubblePlayerRegistry instance =
      _AudioBubblePlayerRegistry._();

  final Set<AudioPlayer> _players = <AudioPlayer>{};

  void register(AudioPlayer p) => _players.add(p);
  void unregister(AudioPlayer p) => _players.remove(p);

  void stopOthers(AudioPlayer me) {
    for (final p in _players) {
      if (identical(p, me)) continue;
      // Best-effort — we don't await so the new playback isn't blocked
      // by a stale reference's pause latency.
      // ignore: discarded_futures
      p.pause();
    }
  }
}

class _Waveform extends StatelessWidget {
  final List<int>? peaks;
  final Color color;
  /// 0.0..1.0 fill progress used by inline playback to colour-fill the
  /// portion of bars the head has crossed. Default 0 = no fill (plain
  /// idle waveform).
  final double progress;
  const _Waveform({
    required this.peaks,
    required this.color,
    this.progress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final samples = peaks ?? List<int>.filled(40, 6);
    return LayoutBuilder(builder: (_, c) {
      final barWidth = (c.maxWidth / samples.length).clamp(1.0, 4.0);
      final filledIndex = (samples.length * progress).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(samples.length, (i) {
          final v = samples[i];
          final filled = i < filledIndex;
          return Container(
            width: barWidth,
            height: (v.clamp(2, 100) / 100.0) * c.maxHeight,
            decoration: BoxDecoration(
              color: filled
                  ? color
                  : color.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(barWidth / 2),
            ),
          );
        }),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCUMENT
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentBubble extends StatelessWidget {
  final ChatMediaPayload payload;
  final AzamanColors colors;
  const _DocumentBubble({required this.payload, required this.colors});

  @override
  Widget build(BuildContext context) {
    final filename = payload.url?.split('/').last ?? 'Document';
    final size = _formatBytes(payload.size);
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _openInSystemViewer(context, payload);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconForMime(payload.mimeType),
                  color: colors.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (size.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        size,
                        style: TextStyle(
                            color: colors.textTertiary, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.download_outlined,
                color: colors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }

  IconData _iconForMime(String? mime) {
    if (mime == null) return Icons.insert_drive_file_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('word') || mime.contains('msword')) {
      return Icons.note_outlined;
    }
    if (mime.contains('excel') || mime.contains('spreadsheet')) {
      return Icons.grid_on_outlined;
    }
    if (mime.contains('presentation')) return Icons.movie_outlined;
    if (mime.startsWith('text')) return Icons.note_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LINK
// ─────────────────────────────────────────────────────────────────────────────

class _LinkBubble extends StatelessWidget {
  final ChatMediaPayload payload;
  final AzamanColors colors;
  const _LinkBubble({required this.payload, required this.colors});

  @override
  Widget build(BuildContext context) {
    final preview = payload.linkPreview;
    final url = payload.caption ?? preview?.url ?? '';

    Future<void> open() async {
      if (url.isEmpty) return;
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      HapticFeedback.lightImpact();
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (preview == null || !preview.hasUsefulMetadata) {
      return GestureDetector(
        onTap: open,
        child: Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Icon(Icons.link, color: colors.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: open,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preview.image != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(imageUrl: 
                  preview.image!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(color: colors.surface),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (preview.siteName != null)
                    Text(
                      preview.siteName!.toUpperCase(),
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  if (preview.title != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  if (preview.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        height: 1.35,
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared placeholders
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingTile extends StatelessWidget {
  final AzamanColors colors;
  final double height;
  const _LoadingTile({required this.colors, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: height,
      color: colors.card,
      alignment: Alignment.center,
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.accent,
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final AzamanColors colors;
  final IconData icon;
  final String label;
  const _ErrorTile({
    required this.colors,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 160,
      color: colors.card,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.textTertiary, size: 28),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(color: colors.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }
}

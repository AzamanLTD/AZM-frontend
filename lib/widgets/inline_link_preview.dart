// =============================================================================
// AZAMAN — Inline Link Preview
//
// Detects URLs in text messages and shows a rich Open Graph preview card
// below the text (like WhatsApp/Telegram iMessage link previews).
//
// The backend caches link previews via /chat/link-preview endpoint.
// This widget fetches lazily and caches in-memory to avoid refetching.
//
// Reference: WhatsApp inline link preview, Telegram URL preview
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/chat_media_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ── URL Detection ───────────────────────────────────────────────────────────

/// Regex to detect URLs in text. Matches http(s):// and bare domain URLs.
final _urlRegex = RegExp(
  r'https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
  caseSensitive: false,
);

/// Extract the first URL from a text string, or null if none found.
String? extractUrl(String text) {
  final match = _urlRegex.firstMatch(text);
  return match?.group(0);
}

// ── In-Memory Cache ──────────────────────────────────────────────────────────

final _previewCache = <String, LinkPreview?>{};

// ── Inline Link Preview Widget ───────────────────────────────────────────────

class InlineLinkPreview extends ConsumerStatefulWidget {
  final String text;
  final bool isMe;

  const InlineLinkPreview({
    super.key,
    required this.text,
    required this.isMe,
  });

  @override
  ConsumerState<InlineLinkPreview> createState() => _InlineLinkPreviewState();
}

class _InlineLinkPreviewState extends ConsumerState<InlineLinkPreview> {
  LinkPreview? _preview;
  bool _loading = true;
  String? _url;

  @override
  void initState() {
    super.initState();
    _url = extractUrl(widget.text);
    if (_url != null) {
      _fetchPreview();
    } else {
      _loading = false;
    }
  }

  Future<void> _fetchPreview() async {
    if (_url == null) return;

    // Check cache first
    if (_previewCache.containsKey(_url)) {
      if (mounted) {
        setState(() {
          _preview = _previewCache[_url];
          _loading = false;
        });
      }
      return;
    }

    try {
      final apiClient = ApiClient();
      final res = await apiClient.post('/chat/link-preview', {'url': _url});
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final previewData = body['preview'];
        if (previewData is Map<String, dynamic>) {
          final preview = LinkPreview.fromJson(previewData);
          _previewCache[_url!] = preview;
          if (mounted) {
            setState(() {
              _preview = preview;
              _loading = false;
            });
          }
          return;
        }
      }
      // No preview available
      _previewCache[_url!] = null;
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      _previewCache[_url!] = null;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_url == null) return const SizedBox.shrink();
    if (_loading) {
      return _buildSkeleton(context);
    }
    if (_preview == null || !_preview!.hasUsefulMetadata) {
      return const SizedBox.shrink();
    }

    return _buildPreviewCard(context).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildSkeleton(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 100,
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 80, height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 200, height: 12,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 160, height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview!;

    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(_url!);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preview.image != null && preview.image!.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(imageUrl: 
                  preview.image!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (preview.siteName != null && preview.siteName!.isNotEmpty)
                    Text(
                      preview.siteName!.toUpperCase(),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  if (preview.title != null && preview.title!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  if (preview.description != null && preview.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
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

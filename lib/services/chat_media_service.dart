// =============================================================================
// CHAT MEDIA SERVICE — Phase UI-3 (2026-05-26)
//
// Wraps the four typed multipart upload endpoints and the link-preview
// endpoint shipped in BE PR Phase UI-3:
//
//   • POST /api/chat/upload/image    → 10MB, jpg/png/webp/heic/gif
//   • POST /api/chat/upload/audio    →  5MB, m4a/mp4/webm/ogg/aac/wav
//   • POST /api/chat/upload/video    → 50MB, mp4/mov/webm
//   • POST /api/chat/upload/document → 25MB, pdf/docx/xlsx/pptx/txt/csv
//   • POST /api/chat/link-preview    → returns Open Graph metadata
//
// Returns typed `ChatMediaUploadResult` envelopes that callers feed into
// `directMessageController.sendMessage` (or the future ticket message
// endpoint) alongside `messageType: IMAGE | VIDEO | AUDIO | DOCUMENT | LINK`.
//
// This service is the single entry point for Tasks 4 and 5 to attach media
// to ticket messages and to render media-vault grids.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:azaman/services/api_client.dart';

/// Canonical envelope returned by every typed upload. Fields are nullable
/// because not every kind populates every field (audio carries duration +
/// waveform, video carries duration only, image/document carry neither).
class ChatMediaUploadResult {
  final String url;
  final String? mimeType;
  final int? size;
  final String? filename;
  final int? duration;
  final List<int>? waveformPeaks;

  const ChatMediaUploadResult({
    required this.url,
    this.mimeType,
    this.size,
    this.filename,
    this.duration,
    this.waveformPeaks,
  });

  factory ChatMediaUploadResult.fromJson(Map<String, dynamic> json) {
    final waveform = json['waveformPeaks'];
    return ChatMediaUploadResult(
      url: (json['url'] ?? '').toString(),
      mimeType: json['mimeType']?.toString(),
      size: json['size'] is int ? json['size'] as int : null,
      filename: json['filename']?.toString(),
      duration: json['duration'] is int ? json['duration'] as int : null,
      waveformPeaks: waveform is List ? waveform.whereType<int>().toList() : null,
    );
  }
}

/// Server-fetched Open Graph metadata for a URL. Mirror of the
/// `LinkPreviewCache` row shape with a `status` discriminator so the FE
/// can render a plain link if the server couldn't resolve the metadata.
class LinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? image;
  final String? favicon;
  final String? siteName;
  final String status;

  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
    this.favicon,
    this.siteName,
    this.status = 'OK',
  });

  bool get hasUsefulMetadata =>
      status == 'OK' && (title != null || description != null || image != null);

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    return LinkPreview(
      url: (json['url'] ?? '').toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      image: json['image']?.toString(),
      favicon: json['favicon']?.toString(),
      siteName: json['siteName']?.toString(),
      status: (json['status'] ?? 'OK').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (image != null) 'image': image,
        if (favicon != null) 'favicon': favicon,
        if (siteName != null) 'siteName': siteName,
        'status': status,
      };
}

class ChatMediaService {
  ChatMediaService._();
  static final ChatMediaService instance = ChatMediaService._();

  /// Upload a still image (camera or gallery). Backend caps at 10MB and only
  /// accepts `image/*` mime types.
  Future<ChatMediaUploadResult> uploadImage(File file) =>
      _uploadFile(endpoint: '/chat/upload/image', file: file);

  /// Upload a voice note. `duration` (seconds) and `waveformPeaks` (50-bucket
  /// integer array) are optional but strongly recommended — the server stores
  /// both verbatim so the receiver bubble can render the waveform and label
  /// without re-decoding the audio.
  Future<ChatMediaUploadResult> uploadAudio(
    File file, {
    int? durationSeconds,
    List<int>? waveformPeaks,
  }) =>
      _uploadFile(
        endpoint: '/chat/upload/audio',
        file: file,
        extraFields: {
          if (durationSeconds != null) 'duration': '$durationSeconds',
          if (waveformPeaks != null) 'waveformPeaks': jsonEncode(waveformPeaks),
        },
      );

  /// Upload a video. `duration` (seconds) is optional. The backend caps at
  /// 50MB; longer-than-2-minute clips should be transcoded client-side first.
  Future<ChatMediaUploadResult> uploadVideo(
    File file, {
    int? durationSeconds,
  }) =>
      _uploadFile(
        endpoint: '/chat/upload/video',
        file: file,
        extraFields: {
          if (durationSeconds != null) 'duration': '$durationSeconds',
        },
      );

  /// Upload a document (PDF, Word, Excel, etc.). Backend caps at 25MB.
  Future<ChatMediaUploadResult> uploadDocument(File file) =>
      _uploadFile(endpoint: '/chat/upload/document', file: file);

  /// Resolve Open Graph metadata for a URL. Server caches successful fetches
  /// for 24h and failures for 1h, so calling this on every message render is
  /// safe — the network round-trip happens at most once per URL per day.
  Future<LinkPreview?> fetchLinkPreview(String url) async {
    if (url.isEmpty) return null;
    try {
      final res = await apiClient.post('/chat/link-preview', {'url': url});
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final preview = body['preview'];
      if (preview is Map<String, dynamic>) {
        return LinkPreview.fromJson(preview);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<ChatMediaUploadResult> _uploadFile({
    required String endpoint,
    required File file,
    Map<String, String> extraFields = const {},
  }) async {
    final uri = Uri.parse('${ApiClient.baseUrl}$endpoint');
    final request = http.MultipartRequest('POST', uri);
    request.fields.addAll(extraFields);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: _guessMediaType(file.path),
      ),
    );
    final response = await apiClient.multipart(endpoint, request);
    if (response.statusCode != 200) {
      throw ChatMediaUploadException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const ChatMediaUploadException(
        statusCode: 0,
        body: 'Malformed response',
      );
    }
    return ChatMediaUploadResult.fromJson(body);
  }

  /// Best-effort mime guess from extension. The backend has its own filter so
  /// this is purely to label the upload for nicer error messages and to set
  /// Content-Type on the multipart part.
  MediaType? _guessMediaType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'webp':
        return MediaType('image', 'webp');
      case 'heic':
        return MediaType('image', 'heic');
      case 'm4a':
      case 'mp4a':
        return MediaType('audio', 'mp4');
      case 'mp3':
        return MediaType('audio', 'mpeg');
      case 'webm':
        return MediaType('audio', 'webm');
      case 'ogg':
      case 'oga':
        return MediaType('audio', 'ogg');
      case 'wav':
        return MediaType('audio', 'wav');
      case 'aac':
        return MediaType('audio', 'aac');
      case 'mp4':
      case 'mov':
        return MediaType('video', 'mp4');
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'doc':
        return MediaType('application', 'msword');
      case 'docx':
        return MediaType(
            'application',
            'vnd.openxmlformats-officedocument.wordprocessingml.document');
      case 'xls':
        return MediaType('application', 'vnd.ms-excel');
      case 'xlsx':
        return MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      case 'ppt':
        return MediaType('application', 'vnd.ms-powerpoint');
      case 'pptx':
        return MediaType(
            'application',
            'vnd.openxmlformats-officedocument.presentationml.presentation');
      case 'txt':
        return MediaType('text', 'plain');
      case 'csv':
        return MediaType('text', 'csv');
      default:
        return null;
    }
  }
}

class ChatMediaUploadException implements Exception {
  final int statusCode;
  final String body;
  const ChatMediaUploadException({
    required this.statusCode,
    required this.body,
  });

  @override
  String toString() => 'ChatMediaUploadException($statusCode): $body';
}

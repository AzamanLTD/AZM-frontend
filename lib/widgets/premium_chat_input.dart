// lib/widgets/premium_chat_input.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/models/chat_message.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/chat_media_service.dart';
import 'package:azaman/widgets/audio_recorder_button.dart';

class PremiumChatInput extends ConsumerStatefulWidget {
  final ChatMessage? replyTo;        // non-null = reply mode active
  final VoidCallback? onClearReply;
  final void Function(String text) onSendText;
  final void Function({
    required String mediaUrl,
    required String mediaType,
    required String messageType,
    String? mimeType, int? size, int? duration,
    List<int>? waveformPeaks,
    Map<String,dynamic>? linkPreview,
    String? caption,
  }) onSendMedia;
  final void Function(bool isTyping) onTypingChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  const PremiumChatInput({
    super.key,
    this.replyTo,
    this.onClearReply,
    required this.onSendText,
    required this.onSendMedia,
    required this.onTypingChanged,
    this.controller,
    this.focusNode,
  });

  @override
  ConsumerState<PremiumChatInput> createState() => _State();
}

class _State extends ConsumerState<PremiumChatInput> {
  late TextEditingController _ctrl;
  late FocusNode _focus;
  bool _hasText = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  Timer? _typingTimer;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    _focus = widget.focusNode ?? FocusNode();
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    if (widget.controller == null) _ctrl.dispose(); 
    if (widget.focusNode == null) _focus.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final has = _ctrl.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    // Typing indicator: emit isTyping=true, debounce stop to 3s
    if (has) {
      widget.onTypingChanged(true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        widget.onTypingChanged(false);
      });
    } else {
      _typingTimer?.cancel();
      widget.onTypingChanged(false);
    }
  }

  void _handleSend() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onSendText(t);
    _ctrl.clear();
    _typingTimer?.cancel();
    widget.onTypingChanged(false);
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    setState(() { _isUploading = true; _uploadProgress = 0; });
    try {
      final r = await ChatMediaService.instance.uploadImage(File(file.path));
      widget.onSendMedia(
        mediaUrl: r.url, mediaType: 'image',
        messageType: 'IMAGE', mimeType: r.mimeType, size: r.size);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed. Try again.')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    setState(() { _isUploading = true; _uploadProgress = 0; });
    try {
      final r = await ChatMediaService.instance.uploadDocument(File(path));
      widget.onSendMedia(
        mediaUrl: r.url, mediaType: 'document',
        messageType: 'DOCUMENT', mimeType: r.mimeType,
        size: r.size);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed. Try again.')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showAttachMenu(BuildContext ctx, AzamanColors c) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttachSheet(
        colors: c,
        onCamera:   () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
        onGallery:  () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
        onDocument: () { Navigator.pop(ctx); _pickDocument(); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(themeProvider).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Reply preview strip ─────────────────────────────────────────
        if (widget.replyTo != null)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: c.accent.withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(left: BorderSide(color: c.accent, width: 3))),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.replyTo!.senderUsername ?? 'Message',
                      style: TextStyle(color: c.accent,
                        fontSize: 11, fontWeight: FontWeight.w700)),
                    Text(widget.replyTo!.text, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  ],
                )),
                GestureDetector(
                  onTap: widget.onClearReply,
                  child: Icon(Icons.close_rounded, size: 18, color: c.textTertiary)),
              ]),
            ),
          ),
        // ── Upload progress bar ──────────────────────────────────────────
        if (_isUploading)
          LinearProgressIndicator(
            value: _uploadProgress > 0 ? _uploadProgress : null,
            backgroundColor: c.divider,
            valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            minHeight: 2),
        // ── Input row ────────────────────────────────────────────────────
        Container(
          color: c.surface,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Attach button
            GestureDetector(
              onTap: () => _showAttachMenu(context, c),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: c.softSurface, shape: BoxShape.circle),
                child: Icon(HugeIconsSolid.attachment01, size: 20, color: c.textSecondary)),
            ),
            const SizedBox(width: 8),
            // Text field
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(color: c.textPrimary, fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: c.textTertiary, fontSize: 14.5),
                    filled: true,
                    fillColor: c.softSurface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button or voice recorder
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
              child: _hasText
                ? GestureDetector(
                    key: const ValueKey('send'),
                    onTap: _handleSend,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: c.accent, shape: BoxShape.circle),
                      child: Icon(HugeIconsSolid.sent,
                        size: 20, color: Colors.white)),
                  )
                : AudioRecorderButton(
                    key: const ValueKey('mic'),
                    onRecorded: (File file, int duration, List<int> peaks) async {
                      setState(() => _isUploading = true);
                      try {
                        final r = await ChatMediaService.instance.uploadAudio(
                          file, durationSeconds: duration, waveformPeaks: peaks);
                        widget.onSendMedia(
                          mediaUrl: r.url, mediaType: 'audio',
                          messageType: 'AUDIO', mimeType: r.mimeType,
                          duration: r.duration ?? duration,
                          waveformPeaks: r.waveformPeaks ?? peaks);
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Voice upload failed.')));
                      } finally {
                        if (mounted) setState(() => _isUploading = false);
                      }
                    },
                  ),
            ),
          ]),
        ),
      ],
    );
  }
}

// ── ATTACH SHEET ────────────────────────────────────────────────────────────
class _AttachSheet extends StatelessWidget {
  final AzamanColors colors;
  final VoidCallback onCamera, onGallery, onDocument;
  const _AttachSheet({required this.colors, required this.onCamera,
    required this.onGallery, required this.onDocument});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _SheetBtn(icon: HugeIconsSolid.camera01, label: 'Camera',
            colors: colors, onTap: onCamera),
          _SheetBtn(icon: HugeIconsSolid.image01, label: 'Gallery',
            colors: colors, onTap: onGallery),
          _SheetBtn(icon: HugeIconsSolid.folder01, label: 'Document',
            colors: colors, onTap: onDocument),
        ]),
      ]),
    );
  }
}

class _SheetBtn extends StatelessWidget {
  final IconData icon; final String label;
  final AzamanColors colors; final VoidCallback onTap;
  const _SheetBtn({required this.icon, required this.label,
    required this.colors, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: colors.accent.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 26, color: colors.accent)),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
      ]),
    );
  }
}


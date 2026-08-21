// lib/widgets/premium_chat_input.dart
// =============================================================================
// Floating Chat Input Bar — pill-shaped floating bar matching the bottom nav
// bar's dimensions and style. Contains: + menu, text field, send/voice button.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:azaman/models/chat_message.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/chat_media_service.dart';
import 'package:azaman/widgets/audio_recorder_button.dart';
import 'package:azaman/widgets/liquid/liquid_dropdown_menu.dart';
import 'package:azaman/widgets/azaman_send_button.dart';

class PremiumChatInput extends ConsumerStatefulWidget {
  final ChatMessage? replyTo;
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
  final VoidCallback? onTransfer;
  final VoidCallback? onTickets;

  const PremiumChatInput({
    super.key,
    this.replyTo,
    this.onClearReply,
    required this.onSendText,
    required this.onSendMedia,
    required this.onTypingChanged,
    this.controller,
    this.focusNode,
    this.onTransfer,
    this.onTickets,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed. Try again.')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(themeProvider).colors;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Reply preview strip ─────────────────────────────────────────
        if (widget.replyTo != null)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.08),
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

        // ── Floating pill bar ────────────────────────────────────────────
        // Same style as PremiumBottomNav: floating pill with surface color,
        // rounded corners, shadow. Contains + button, text field, send/voice.
        // Dimensions match the nav bar (height 62, radius 31) so the
        // transition between nav bar and chat input feels seamless.
        Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, bottom > 0 ? bottom + 8 : 16),
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(31),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: c.isDark ? 0.45 : 0.13),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // ── Attach (plus) button ──
                LiquidDropdownMenu(
                  colors: c,
                  size: 36,
                  items: [
                    LiquidDropdownItem(
                      icon: Icons.camera_alt_outlined,
                      label: 'Camera',
                      onTap: () => _pickImage(ImageSource.camera),
                    ),
                    LiquidDropdownItem(
                      icon: Icons.image_outlined,
                      label: 'Gallery',
                      onTap: () => _pickImage(ImageSource.gallery),
                    ),
                    LiquidDropdownItem(
                      icon: Icons.folder_outlined,
                      label: 'Document',
                      onTap: _pickDocument,
                    ),
                    if (widget.onTransfer != null)
                      LiquidDropdownItem(
                        icon: Icons.compare_arrows_rounded,
                        label: 'Transfer',
                        onTap: widget.onTransfer!,
                      ),
                    if (widget.onTickets != null)
                      LiquidDropdownItem(
                        icon: Icons.confirmation_number_outlined,
                        label: 'Tickets',
                        onTap: widget.onTickets!,
                      ),
                  ],
                ),
                // ── Text field ──
                Expanded(
                  child: IgnorePointer(
                    ignoring: _isRecording,
                    child: Opacity(
                      opacity: _isRecording ? 0.0 : 1.0,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 100),
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          maxLines: null,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(color: c.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Message',
                            hintStyle: TextStyle(color: c.textTertiary, fontSize: 14),
                            filled: true,
                            fillColor: c.softSurface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Send / Voice button ──
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                  child: _hasText
                    ? AzamanSendButton(
                        key: const ValueKey('send'),
                        accentColor: c.accent,
                        outlineColor: c.isDark ? Colors.white : Colors.white,
                        fillColor: c.isDark ? Colors.white : Colors.white,
                        onSend: _handleSend,
                        isDark: c.isDark,
                      )
                    : Padding(
                        key: const ValueKey('mic'),
                        padding: const EdgeInsets.only(right: 4),
                        child: AudioRecorderButton(
                          onRecordingStateChanged: (rec) {
                            if (mounted) setState(() => _isRecording = rec);
                          },
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
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Voice upload failed.')));
                              }
                            } finally {
                              if (mounted) setState(() => _isUploading = false);
                            }
                          },
                        ),
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

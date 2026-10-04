// =============================================================================
// AZAMAN — STORY VIEWER: INTERACTION BAR
//
// Renders ONLY affordances the gateway's capability set actually supports
// (Overhaul 05 §6.2). Today the backend has no /stories/:id/reply route, so
// with the real gateway this bar renders NOTHING and the page drops it from
// the tree entirely — no dead reply field, no fake "Reply sent!" snackbar
// over a 404. The bar exists so the capability seam is exercised and tested:
// when the route lands, adding `StoryCapability.reply` to the gateway makes
// the field appear with zero further changes.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/experience/gateways/az_gateway_result.dart';
import 'package:azaman/experience/gateways/story_gateway.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class StoryInteractionBar extends ConsumerStatefulWidget {
  const StoryInteractionBar({
    super.key,
    required this.story,
    required this.authorId,
    required this.onFocusChanged,
  });

  final StoryItem story;
  final int authorId;

  /// Focus on the reply field pauses playback; blur resumes.
  final ValueChanged<bool> onFocusChanged;

  @override
  ConsumerState<StoryInteractionBar> createState() =>
      _StoryInteractionBarState();
}

class _StoryInteractionBarState extends ConsumerState<StoryInteractionBar> {
  final _replyController = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  bool get _canReply =>
      ref.read(storyGatewayProvider).capabilities
          .contains(StoryCapability.reply);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() => widget.onFocusChanged(_focus.hasFocus);

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final message = _replyController.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() => _sending = true);
    AzamanHaptics.selection();
    final result =
        await ref.read(storyGatewayProvider).reply(widget.story.id, message);
    if (!mounted) return;
    setState(() => _sending = false);
    switch (result) {
      case AzOk<void>():
        _replyController.clear();
        AzamanHaptics.confirm();
        _toast('Reply sent');
      case AzFailed<void>(:final message):
        _toast(message);
      case AzUnsupported<void>():
        // Unreachable while reply is hidden by capability; kept honest.
        _toast('Replies aren\'t available yet');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canReply) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AzSpace.lg, 0, AzSpace.lg, AzSpace.md),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AzSpace.md),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AzRadius.pill),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        color: Colors.white.withValues(alpha: 0.6), size: 20),
                    const SizedBox(width: AzSpace.sm),
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        focusNode: _focus,
                        style:
                            AzText.body.copyWith(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Reply to story…',
                          hintStyle: AzText.body
                              .copyWith(color: Colors.white.withValues(alpha: 0.4)),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _sendReply(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AzSpace.sm),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _replyController,
              builder: (context, value, _) => GestureDetector(
                onTap: _sendReply,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: value.text.trim().isEmpty
                        ? Colors.white.withValues(alpha: 0.1)
                        : colors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : Icon(Icons.send,
                          color: value.text.trim().isEmpty
                              ? Colors.white.withValues(alpha: 0.7)
                              : Colors.black,
                          size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

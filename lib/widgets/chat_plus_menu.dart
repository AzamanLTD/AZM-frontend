// =============================================================================
// CHAT PLUS MENU — 2026-07-08 sprint, reworked twice this sprint
//
// v1 (original): options stacked vertically directly above the "+" button
// as individual floating circular bubbles (iMessage-style) -- but the
// tap-outside-to-close scrim only covered the widget's own internal Stack
// (never rendered through an Overlay), so it never really covered the
// screen.
// v2 (first rework): fixed the scrim by moving to a real OverlayEntry, but
// changed the visual to a single rounded-rect dropdown card -- turned out
// Stan specifically liked the original iMessage-style vertical bubble stack
// and wanted that look kept.
// v3 (this version): keeps v2's real OverlayEntry/full-screen-scrim fix,
// but restores v1's visual -- individual circular icon bubbles (with a
// label chip beside each) stacked vertically, growing directly upward from
// the "+" button itself, staggered scale+fade entrance.
// =============================================================================
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';

class ChatPlusMenu extends StatefulWidget {
  final VoidCallback? onImageTap;
  final VoidCallback? onDocumentTap;
  final VoidCallback? onStickerTap;
  final VoidCallback? onTransferTap;
  final VoidCallback? onEscrowTap;

  const ChatPlusMenu({
    super.key,
    this.onImageTap,
    this.onDocumentTap,
    this.onStickerTap,
    this.onTransferTap,
    this.onEscrowTap,
  });

  @override
  State<ChatPlusMenu> createState() => _ChatPlusMenuState();
}

class _ChatPlusMenuState extends State<ChatPlusMenu>
    with SingleTickerProviderStateMixin {
  final GlobalKey _anchorKey = GlobalKey();
  late final AnimationController _controller;
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  List<_MenuItem> _buildItems() {
    final items = <_MenuItem>[];
    if (widget.onImageTap != null) {
      items.add(_MenuItem(icon: Icons.image_outlined, label: 'Image', onTap: widget.onImageTap!));
    }
    if (widget.onDocumentTap != null) {
      items.add(_MenuItem(icon: Icons.folder_outlined, label: 'Document', onTap: widget.onDocumentTap!));
    }
    if (widget.onStickerTap != null) {
      items.add(_MenuItem(icon: Icons.emoji_emotions_outlined, label: 'Sticker', onTap: widget.onStickerTap!));
    }
    if (widget.onTransferTap != null) {
      items.add(_MenuItem(icon: Icons.compare_arrows_rounded, label: 'Transfer', onTap: widget.onTransferTap!));
    }
    if (widget.onEscrowTap != null) {
      items.add(_MenuItem(icon: Icons.receipt_long_rounded, label: 'Ticket (Escrow)', onTap: widget.onEscrowTap!));
    }
    return items;
  }

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final items = _buildItems();
    if (items.isEmpty) return;

    final colors = Theme.of(context).extension<AzamanColors>()!;
    final renderBox = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorPos = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Real full-screen scrim — tapping anywhere closes the menu.
          // (This was the actual bug in the original v1: its scrim only
          // ever covered its own internal Stack, not the real screen.)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: FadeTransition(
                opacity: _controller,
                child: Container(color: Colors.black.withOpacity(0.16)),
              ),
            ),
          ),
          // The bubble stack itself grows directly upward from the "+"
          // button's own screen position.
          Positioned(
            left: anchorPos.dx,
            bottom: screenHeight - anchorPos.dy + 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < items.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i < items.length - 1 ? 12.0 : 0),
                    child: _StaggeredBubble(
                      controller: _controller,
                      index: i,
                      count: items.length,
                      item: items[i],
                      colors: colors,
                      onTap: () {
                        _close();
                        items[i].onTap();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
    _controller.forward(from: 0);
  }

  void _close() {
    if (!_isOpen) return;
    _controller.reverse().whenComplete(_removeOverlay);
    setState(() => _isOpen = false);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AzamanColors>()!;
    return GestureDetector(
      key: _anchorKey,
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Transform.rotate(
          angle: _controller.value * 0.785398, // 45°
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surface,
              border: Border.all(color: colors.accent, width: 1.5),
            ),
            child: Icon(Icons.add, color: colors.accent, size: 20),
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({required this.icon, required this.label, required this.onTap});
}

/// One bubble in the vertical stack: a small rounded label chip beside a
/// circular icon button, fading + rising into place with a stagger based
/// on its position in the stack (items nearest the "+" button settle in
/// first).
class _StaggeredBubble extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final int count;
  final _MenuItem item;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _StaggeredBubble({
    required this.controller,
    required this.index,
    required this.count,
    required this.item,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Items are laid out top-to-bottom as [farthest ... nearest the button].
    // Reverse the stagger so the item closest to the button (last in the
    // list) animates in first, like it's "popping out" of the button.
    final reverseIndex = count - 1 - index;
    final start = reverseIndex / count;
    final end = (reverseIndex + 1.4).clamp(0, count) / count;
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0), curve: Curves.easeOutBack),
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 24.0 * (1.0 - t)),
            child: Transform.scale(scale: 0.6 + (0.4 * t), alignment: Alignment.bottomLeft, child: child),
          ),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colors.surface.withOpacity(0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.divider),
              ),
              child: Text(
                item.label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surface,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accentSurface,
                    ),
                    child: Icon(item.icon, color: colors.accent, size: 19),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

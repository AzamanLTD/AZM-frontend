// =============================================================================
// CHAT PLUS MENU — 2026-07-08 UI/UX sprint rework
//
// Was a stack of separate floating circular bubbles, each staggering in with
// its own fade+translateY, plus a broken tap-outside scrim (it only covered
// the widget's own internal Stack, not the actual screen, since it wasn't
// rendered through an Overlay). Replaced with a proper OverlayEntry-based
// popup: a single rounded-rect card that grows from the "+" button with a
// container-transform-style scale+fade, holding a clean vertical list of
// rows separated by hairline dividers — and a real full-screen scrim behind
// it so tapping anywhere else genuinely closes the menu.
// =============================================================================
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
      duration: const Duration(milliseconds: 260),
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

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Real full-screen scrim — tapping anywhere closes the menu.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: FadeTransition(
                opacity: _controller,
                child: Container(color: Colors.black.withOpacity(0.18)),
              ),
            ),
          ),
          Positioned(
            left: anchorPos.dx,
            bottom: MediaQuery.of(context).size.height - anchorPos.dy + 10,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
              alignment: Alignment.bottomLeft,
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _controller,
                  curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
                ),
                child: _MenuCard(
                  items: items,
                  colors: colors,
                  onItemTap: (item) {
                    _close();
                    item.onTap();
                  },
                ),
              ),
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

class _MenuCard extends StatelessWidget {
  final List<_MenuItem> items;
  final AzamanColors colors;
  final ValueChanged<_MenuItem> onItemTap;

  const _MenuCard({required this.items, required this.colors, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 210,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: colors.divider),
              _row(items[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(_MenuItem item) {
    return InkWell(
      onTap: () => onItemTap(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accentSurface,
              ),
              child: Icon(item.icon, color: colors.accent, size: 17),
            ),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(color: colors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

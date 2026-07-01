import 'dart:math' as math;
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
  late AnimationController _controller;
  late Animation<double> _menuItemsAnim;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _menuItemsAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 1.0, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _close() {
    if (_isOpen) {
      setState(() => _isOpen = false);
      _controller.reverse();
    }
  }

  void _handleTap(VoidCallback? callback) {
    _close();
    callback?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AzamanColors>()!;

    final items = <_MenuItem>[];
    if (widget.onImageTap != null) {
      items.add(_MenuItem(
        icon: Icons.image_outlined,
        label: 'Image',
        onTap: () => _handleTap(widget.onImageTap),
      ));
    }
    if (widget.onDocumentTap != null) {
      items.add(_MenuItem(
        icon: Icons.folder_outlined,
        label: 'Document',
        onTap: () => _handleTap(widget.onDocumentTap),
      ));
    }
    if (widget.onStickerTap != null) {
      items.add(_MenuItem(
        icon: Icons.emoji_emotions_outlined,
        label: 'Sticker',
        onTap: () => _handleTap(widget.onStickerTap),
      ));
    }
    if (widget.onTransferTap != null) {
      items.add(_MenuItem(
        icon: Icons.compare_arrows,
        label: 'Transfer',
        onTap: () => _handleTap(widget.onTransferTap),
      ));
    }
    if (widget.onEscrowTap != null) {
      items.add(_MenuItem(
        icon: Icons.receipt_long_rounded,
        label: 'Ticket (Escrow)',
        onTap: () => _handleTap(widget.onEscrowTap),
      ));
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: Container(color: Colors.transparent),
            ),
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(items.length, (i) {
              final item = items[i];
              return AnimatedBuilder(
                animation: _menuItemsAnim,
                builder: (context, child) {
                  final progress = _menuItemsAnim.value;
                  final adjusted = math.max(
                    0.0,
                    (progress * items.length - i) / (items.length - i),
                  );
                  final opacity = adjusted.clamp(0.0, 1.0);
                  final translateY = 50.0 * (1.0 - adjusted);
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: i < items.length - 1 ? 12.0 : 0,
                    ),
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.translate(
                        offset: Offset(0, translateY),
                        child: child,
                      ),
                    ),
                  );
                },
                child: MenuItemWidget(
                  icon: item.icon,
                  label: item.label,
                  colors: colors,
                  onTap: item.onTap,
                ),
              );
            }),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _toggle,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Transform.rotate(
                    angle: _controller.value * math.pi / 4,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.surface,
                        border: Border.all(
                          color: colors.accent,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.add,
                        color: colors.accent,
                        size: 20,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class MenuItemWidget extends StatelessWidget {
  final IconData icon;
  final String label;
  final AzamanColors colors;
  final VoidCallback onTap;

  const MenuItemWidget({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surface.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surface,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surface.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: colors.accent, size: 18),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

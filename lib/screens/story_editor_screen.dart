// =============================================================================
// AZAMAN — Story Editor Screen
//
// Post-capture editor with:
//   • Text overlay (draggable, rotatable, color picker)
//   • Sticker emojis (draggable)
//   • Doodle/freehand drawing (color + brush size)
//   • Filter selection (from camera or re-apply)
//
// Reference: Instagram Stories editor, Snapchat creative tools, TikTok effects
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/screens/story_camera_screen.dart';

// Available stickers
const _STICKERS = [
  '🔥', '⭐', '❤️', '🎉', '✨', '👏', '💯', '🚀',
  '😂', '😍', '🤩', '👍', '💰', '🏆', '🌟', '🎁',
];

// Text colors
const _TEXT_COLORS = [
  Color(0xFFFFFFFF), Color(0xFF000000),
  Color(0xFFFF0000), Color(0xFF00FF00),
  Color(0xFF00B4D8), Color(0xFFFFD700),
  Color(0xFFFF00FF), Color(0xFF8B4513),
];

enum EditMode { none, text, sticker, draw }

class _OverlayItem {
  final String id;
  final Offset position;
  final double scale;
  final double rotation;
  final String? text;
  final String? sticker;
  final Color color;

  _OverlayItem({
    required this.id,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0,
    this.text,
    this.sticker,
    this.color = Colors.white,
  });

  _OverlayItem copyWith({
    Offset? position,
    double? scale,
    double? rotation,
    String? text,
    String? sticker,
    Color? color,
  }) {
    return _OverlayItem(
      id: id,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      text: text ?? this.text,
      sticker: sticker ?? this.sticker,
      color: color ?? this.color,
    );
  }
}

class StoryEditorScreen extends ConsumerStatefulWidget {
  final File mediaFile;
  final bool isVideo;
  final StoryFilter initialFilter;
  final Function(File mediaFile, bool isVideo) onPublish;

  const StoryEditorScreen({
    super.key,
    required this.mediaFile,
    this.isVideo = false,
    this.initialFilter = StoryFilter.none,
    required this.onPublish,
  });

  @override
  ConsumerState<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends ConsumerState<StoryEditorScreen> {
  EditMode _mode = EditMode.none;
  StoryFilter _filter = StoryFilter.none;
  final List<_OverlayItem> _overlays = [];
  final List<Offset> _drawPoints = [];
  Color _drawColor = Colors.white;
  double _brushSize = 4.0;
  Color _textColor = Colors.white;
  final TextEditingController _textController = TextEditingController();
  int _selectedOverlayIndex = -1;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _addTextOverlay() {
    if (_textController.text.trim().isEmpty) return;
    setState(() {
      _overlays.add(_OverlayItem(
        id: 'overlay_${DateTime.now().millisecondsSinceEpoch}',
        position: Offset(
          MediaQuery.of(context).size.width / 2 - 80,
          MediaQuery.of(context).size.height / 3,
        ),
        text: _textController.text.trim(),
        color: _textColor,
        scale: 1.2,
      ));
      _textController.clear();
      _mode = EditMode.none;
    });
    AzamanHaptics.commit();
  }

  void _addSticker(String sticker) {
    setState(() {
      _overlays.add(_OverlayItem(
        id: 'overlay_${DateTime.now().millisecondsSinceEpoch}',
        position: Offset(
          MediaQuery.of(context).size.width / 2 - 28,
          MediaQuery.of(context).size.height / 3,
        ),
        sticker: sticker,
        scale: 2.0,
      ));
    });
    AzamanHaptics.toggle();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                  const Spacer(),
                  if (_mode != EditMode.none)
                    GestureDetector(
                      onTap: () => setState(() => _mode = EditMode.none),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      AzamanHaptics.confirm();
                      widget.onPublish(widget.mediaFile, widget.isVideo);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Publish',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Media preview with overlays ──
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _mode = EditMode.none;
                    _selectedOverlayIndex = -1;
                  });
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Media
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ColorFiltered(
                        colorFilter: _filter.colorFilter,
                        child: widget.isVideo
                            ? Container(color: Colors.black) // Video placeholder
                            : Image.file(
                                widget.mediaFile,
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),

                    // Doodle drawing layer
                    if (_drawPoints.isNotEmpty)
                      CustomPaint(
                        painter: _DoodlePainter(_drawPoints, _drawColor, _brushSize),
                        size: Size.infinite,
                      ),

                    // Overlay items (text + stickers)
                    ..._overlays.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final isSelected = index == _selectedOverlayIndex;

                      return Positioned(
                        left: item.position.dx,
                        top: item.position.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _overlays[index] = item.copyWith(
                                position: item.position + details.delta,
                              );
                            });
                          },
                          onTap: () {
                            setState(() => _selectedOverlayIndex = index);
                          },
                          child: Transform.scale(
                            scale: item.scale,
                            child: Transform.rotate(
                              angle: item.rotation,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: isSelected
                                    ? BoxDecoration(
                                        border: Border.all(color: colors.accent, width: 1.5),
                                        borderRadius: BorderRadius.circular(8),
                                      )
                                    : null,
                                child: item.text != null
                                    ? Text(
                                        item.text!,
                                        style: TextStyle(
                                          color: item.color,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          shadows: const [
                                            Shadow(
                                              color: Colors.black54,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Text(
                                        item.sticker!,
                                        style: const TextStyle(fontSize: 40),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // ── Text input (when in text mode) ──
            if (_mode == EditMode.text) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Color picker
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _TEXT_COLORS.length,
                        itemBuilder: (context, index) {
                          final c = _TEXT_COLORS[index];
                          return GestureDetector(
                            onTap: () => setState(() => _textColor = c),
                            child: Container(
                              width: 28, height: 28,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _textColor == c ? colors.accent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Type something...',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (_) => _addTextOverlay(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _addTextOverlay,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Sticker picker ──
            if (_mode == EditMode.sticker)
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _STICKERS.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _addSticker(_STICKERS[index]),
                      child: Container(
                        width: 56, height: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(_STICKERS[index], style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ── Draw tools ──
            if (_mode == EditMode.draw)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    ..._TEXT_COLORS.take(5).map((c) => GestureDetector(
                      onTap: () => setState(() => _drawColor = c),
                      child: Container(
                        width: 28, height: 28,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _drawColor == c ? colors.accent : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _brushSize,
                        min: 1,
                        max: 12,
                        activeColor: colors.accent,
                        onChanged: (v) => setState(() => _brushSize = v),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _drawPoints.clear()),
                      child: const Icon(Icons.undo, color: Colors.white70, size: 24),
                    ),
                  ],
                ),
              ),

            // ── Bottom toolbar ──
            if (_mode == EditMode.none)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ToolButton(
                      icon: HugeIconsSolid.text,
                      label: 'Text',
                      onTap: () => setState(() => _mode = EditMode.text),
                      colors: colors,
                    ),
                    _ToolButton(
                      icon: HugeIconsSolid.star,
                      label: 'Sticker',
                      onTap: () => setState(() => _mode = EditMode.sticker),
                      colors: colors,
                    ),
                    _ToolButton(
                      icon: HugeIconsSolid.note01,
                      label: 'Draw',
                      onTap: () => setState(() => _mode = EditMode.draw),
                      colors: colors,
                    ),
                    _ToolButton(
                      icon: HugeIconsSolid.note01,
                      label: 'Filter',
                      onTap: () => _showFilterSheet(colors),
                      colors: colors,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(AzamanColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filters', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: StoryFilter.values.length,
                itemBuilder: (context, index) {
                  final filter = StoryFilter.values[index];
                  final isSelected = filter == _filter;
                  return GestureDetector(
                    onTap: () {
                      AzamanHaptics.nav();
                      setState(() => _filter = filter);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 64,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected ? colors.accent : Colors.transparent,
                                width: 2,
                              ),
                              color: filter.thumbTint,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            filter.label,
                            style: TextStyle(
                              color: isSelected ? colors.accent : Colors.white70,
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final AzamanColors colors;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ).animate().fadeIn(duration: 200.ms),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  _DoodlePainter(this.points, this.color, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != Offset.infinite && points[i + 1] != Offset.infinite) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DoodlePainter oldDelegate) => true;
}

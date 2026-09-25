// lib/widgets/book/page_curl_painter.dart
// =============================================================================
// PAGE CURL PAINTER — everything that touches a Canvas.
//
// Rendering contract (order matters, each step is one GPU draw):
//   1. cast shadow      — blurred silhouette of the lifted sheet on the page
//                         underneath; broadens + softens with lift height
//   2. front face       — drawVertices of the page texture, per-vertex
//                         Lambert shading baked into the vertex colours
//   3. back face        — opaque paper fill, then the same texture at low
//                         alpha so the print "bleeds" through mirrored, then
//                         a darkening gradient toward the fold
//   4. specular crest   — additive sweep along the ridge of the fold
//   5. paper edge       — 1px warm stroke along the crest to imply thickness
//
// There is deliberately no saveLayer anywhere in this file.
// =============================================================================
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'page_geometry.dart';

/// Colour + intensity knobs for the book's material.
@immutable
class BookMaterial {
  /// Base colour of the paper stock (the back of a leaf).
  final Color paper;

  /// Colour of the shadow the lifted page casts on the sheet below.
  final Color castShadow;

  /// Warm edge colour drawn along the fold crest to imply sheet thickness.
  final Color edge;

  /// How much of the front print shows through the back of the sheet.
  final double bleed;

  /// Intensity of the specular highlight along the fold crest.
  final double specularStrength;

  /// Strength of the cast shadow under the lifted sheet.
  final double shadowStrength;

  /// Strength of the inner spine shadow (left edge of the book).
  final double spineStrength;

  const BookMaterial({
    this.paper = const Color(0xFFFBF3E0),
    this.castShadow = const Color(0xFF1A1206),
    this.edge = const Color(0xFFD8C6A2),
    this.bleed = 0.18,
    this.specularStrength = 0.35,
    this.shadowStrength = 0.55,
    this.spineStrength = 0.18,
  });
}

/// Mutable per-frame channel between the widget and the painter.
/// The widget computes the geometry, drops it here, and calls [commit].
/// The painter's `repaint` is this object's `Listenable`, so committing
/// repaints only the CustomPaint — no widget rebuild.
class LeafFrame extends ChangeNotifier {
  ui.Image? texture;
  CurlGeometry? geometry;
  double progress = 0;

  ui.Image? _shaderImage;
  ui.ImageShader? _shader;

  ui.ImageShader? get shader {
    final img = texture;
    if (img == null) {
      _shader = null;
      _shaderImage = null;
      return null;
    }
    if (!identical(img, _shaderImage) || _shader == null) {
      _shaderImage = img;
      _shader = ui.ImageShader(
        img,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.low,
      );
    }
    return _shader;
  }

  void commit({ui.Image? texture, CurlGeometry? geometry, double? progress}) {
    this.texture = texture;
    this.geometry = geometry;
    if (progress != null) this.progress = progress;
    notifyListeners();
  }

  @override
  void dispose() {
    _shader = null;
    _shaderImage = null;
    super.dispose();
  }
}

/// Paints one turning leaf. At rest it paints nothing — the live widgets
/// are visible. Only when a turn is in flight does this painter draw.
class PageCurlPainter extends CustomPainter {
  final LeafFrame frame;
  final BookMaterial material;

  PageCurlPainter({
    required this.frame,
    required this.material,
  }) : super(repaint: frame);

  final Paint _shadowPaint = Paint();
  final Paint _facePaint = Paint()..isAntiAlias = true;
  final Paint _fillPaint = Paint()..isAntiAlias = true;
  final Paint _specPaint = Paint()
    ..isAntiAlias = true
    ..blendMode = BlendMode.plus;
  final Paint _edgePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = frame.geometry;
    if (geo == null) return;

    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);

    final lift = (geo.liftHeight / (size.width * 0.34)).clamp(0.0, 1.0);

    _paintCastShadow(canvas, geo, lift);

    final shader = frame.shader;

    // Front face
    if (geo.frontFace != null) {
      if (shader != null) {
        _facePaint
          ..shader = shader
          ..color = const Color(0xFFFFFFFF);
        canvas.drawVertices(geo.frontFace!, BlendMode.modulate, _facePaint);
        _facePaint.shader = null;
      } else {
        _fillPaint
          ..shader = null
          ..color = material.paper;
        canvas.drawVertices(geo.frontFace!, BlendMode.modulate, _fillPaint);
      }
    }

    // Back face
    if (geo.backFace != null) {
      _fillPaint
        ..shader = null
        ..color = material.paper;
      canvas.drawVertices(geo.backFace!, BlendMode.modulate, _fillPaint);

      if (shader != null && material.bleed > 0) {
        _facePaint
          ..shader = shader
          ..color = Color.fromRGBO(255, 255, 255, material.bleed);
        canvas.drawVertices(geo.backFace!, BlendMode.modulate, _facePaint);
        _facePaint.shader = null;
      }

      _paintUndersideGradient(canvas, geo, lift);
    }

    _paintSpecular(canvas, geo, lift);
    _paintEdge(canvas, geo, lift);

    canvas.restore();
  }

  void _paintCastShadow(Canvas canvas, CurlGeometry geo, double lift) {
    if (lift <= 0.001) return;
    final path = geo.hasBackFace ? geo.backOutline : geo.frontOutline;
    final offset = Offset(geo.liftHeight * 0.16, geo.liftHeight * 0.26);
    final sigma = 3.0 + geo.liftHeight * 0.22;
    _shadowPaint
      ..color = material.castShadow.withValues(
        alpha: material.shadowStrength * (0.35 + 0.65 * lift),
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawPath(path, _shadowPaint);
    canvas.restore();
    _shadowPaint.maskFilter = null;
  }

  void _paintUndersideGradient(Canvas canvas, CurlGeometry geo, double lift) {
    final crestMid = Offset(
      (geo.crestStart.dx + geo.crestEnd.dx) * 0.5,
      (geo.crestStart.dy + geo.crestEnd.dy) * 0.5,
    );
    final u = geo.turnDirection;
    final span = geo.radius * 3.2 + 24;
    final from = crestMid;
    final to = crestMid + Offset(-u.dx * span, -u.dy * span);
    _fillPaint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ui.Gradient.linear(
        from,
        to,
        <Color>[
          material.castShadow.withValues(alpha: 0.30 * (0.4 + 0.6 * lift)),
          material.castShadow.withValues(alpha: 0.06),
          const Color(0x00000000),
        ],
        const <double>[0.0, 0.45, 1.0],
      );
    canvas.drawPath(geo.backOutline, _fillPaint);
    _fillPaint.shader = null;
  }

  void _paintSpecular(Canvas canvas, CurlGeometry geo, double lift) {
    if (lift <= 0.02) return;
    final u = geo.turnDirection;
    final crestMid = Offset(
      (geo.crestStart.dx + geo.crestEnd.dx) * 0.5,
      (geo.crestStart.dy + geo.crestEnd.dy) * 0.5,
    );
    final band = geo.radius * 0.9 + 6;
    final a = crestMid + Offset(u.dx * band, u.dy * band);
    final b = crestMid - Offset(u.dx * band, u.dy * band);
    final intensity = material.specularStrength * (0.25 + 0.75 * lift);
    _specPaint.shader = ui.Gradient.linear(
      a,
      b,
      <Color>[
        const Color(0x00FFFFFF),
        Color.fromRGBO(255, 250, 236, intensity),
        const Color(0x00FFFFFF),
      ],
      const <double>[0.0, 0.5, 1.0],
    );
    final path = Path()
      ..addPath(geo.frontOutline, Offset.zero)
      ..addPath(geo.backOutline, Offset.zero);
    canvas.drawPath(path, _specPaint);
    _specPaint.shader = null;
  }

  void _paintEdge(Canvas canvas, CurlGeometry geo, double lift) {
    if (lift <= 0.02 || geo.crestStart == geo.crestEnd) return;
    _edgePaint
      ..color = material.edge.withValues(alpha: 0.55 * lift)
      ..strokeWidth = 1.2;
    canvas.drawLine(geo.crestStart, geo.crestEnd, _edgePaint);
  }

  @override
  bool shouldRepaint(covariant PageCurlPainter old) =>
      old.frame != frame || old.material != material;

  @override
  bool shouldRebuildSemantics(covariant PageCurlPainter oldDelegate) => false;
}

/// Static chrome painted behind the pages: spine crease + page-block edges.
class BookChromePainter extends CustomPainter {
  final BookMaterial material;
  final double readProgress;

  const BookChromePainter({required this.material, required this.readProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();

    // Spine crease
    final spineWidth = size.width * 0.09;
    paint.shader = ui.Gradient.linear(
      rect.topLeft,
      Offset(spineWidth, 0),
      <Color>[
        material.castShadow.withValues(alpha: material.spineStrength),
        material.castShadow.withValues(alpha: material.spineStrength * 0.35),
        const Color(0x00000000),
      ],
      const <double>[0.0, 0.35, 1.0],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, spineWidth, size.height), paint);

    // Page block on outer edge
    final remaining = (1.0 - readProgress).clamp(0.0, 1.0);
    final blockWidth = 2.0 + 6.0 * remaining;
    paint.shader = ui.Gradient.linear(
      Offset(size.width - blockWidth, 0),
      Offset(size.width, 0),
      <Color>[
        material.paper.withValues(alpha: 0.0),
        material.edge.withValues(alpha: 0.85),
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - blockWidth, 2, blockWidth, size.height - 4),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant BookChromePainter old) =>
      old.material != material || old.readProgress != readProgress;
}

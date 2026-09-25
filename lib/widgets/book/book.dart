// lib/widgets/book/book.dart
// =============================================================================
// Public surface of the in-house 3D page-turn engine.
//
//   flip_physics.dart      — release resolution + spring settle (pure Dart)
//   page_geometry.dart     — cylindrical curl solver → triangle strips
//   page_curl_painter.dart — every Canvas operation (shadow, faces, specular)
//   flip_book_controller.dart — gesture → turn state machine
//   flip_book.dart         — the widget: rasterises a leaf, curls it, lands it
//
// Import this file rather than the parts, so the internals can be reshaped
// without touching call sites.
// =============================================================================
export 'flip_book.dart';
export 'flip_book_controller.dart';
export 'flip_physics.dart';
export 'page_curl_painter.dart' show BookMaterial, LeafFrame;
export 'page_geometry.dart'
    show FlipAnchor, FlipDirection, CurlGeometry, FlipPath, PageCurlSolver;

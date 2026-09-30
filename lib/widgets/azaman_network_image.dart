import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Drop-in replacement for CachedNetworkImage that ALWAYS constrains decode
/// resolution to the actual display size. This is the single biggest image
/// performance fix available in this codebase.
///
/// Accepts the same placeholder/errorWidget builder signatures as
/// CachedNetworkImage so migration is a simple name swap + import change.
/// When [width]/[height] are provided, they're used to compute memCacheWidth/
/// memCacheHeight (× devicePixelRatio). When not provided, LayoutBuilder
/// reads parent constraints at runtime.
///
/// Placeholder and fallback read AzamanColors from the live theme, never M3
/// fallback roles, so a failed load can never leak framework lavender.
class AzamanNetworkImage extends ConsumerWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;

  const AzamanNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider.select((t) => t.colors));
    if (width != null && height != null) {
      return _buildImage(context, colors, width!, height!);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = width ?? constraints.maxWidth;
        final h = height ?? constraints.maxHeight;
        final resolvedW = w.isFinite ? w : 400.0;
        final resolvedH = h.isFinite ? h : 400.0;
        return _buildImage(context, colors, resolvedW, resolvedH);
      },
    );
  }

  Widget _buildImage(
    BuildContext context,
    AzamanColors colors,
    double w,
    double h,
  ) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final targetW = (w * dpr).round();
    final targetH = (h * dpr).round();

    Widget image;
    if (imageUrl == null || imageUrl!.isEmpty) {
      image = _fallback(colors, w, h);
    } else {
      image = CachedNetworkImage(
        imageUrl: imageUrl!,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: targetW,
        memCacheHeight: targetH,
        fadeInDuration: MotionTokens.control,
        placeholder: placeholder ?? (_, __) => _shimmerBlock(colors, w, h),
        errorWidget: errorWidget ?? (_, __, ___) => _fallback(colors, w, h),
      );
    }

    return borderRadius != null
        ? ClipRRect(borderRadius: borderRadius!, child: image)
        : image;
  }

  Widget _shimmerBlock(AzamanColors colors, double w, double h) => Container(
        width: width ?? w,
        height: height ?? h,
        color: colors.softSurface,
      );

  Widget _fallback(AzamanColors colors, double w, double h) => Container(
        width: width ?? w,
        height: height ?? h,
        color: colors.softSurface,
        child: Icon(
          Icons.image_outlined,
          size: (w * 0.35).clamp(16.0, 48.0),
          color: colors.textTertiary,
        ),
      );
}

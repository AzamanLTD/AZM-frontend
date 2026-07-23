// =============================================================================
// Storefront Screen — Customer-facing
//
// Displays a business's published storefront to customers using the SDUI
// renderer. Fires storefront_view on load and wraps all widgets with
// visibility + interaction tracking.
//
// Used from:
//   - Marketplace search results → tap business → storefront tab
//   - Deep links → /storefront/:businessProfileId
//   - QR code scan → storefront
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../storefront/providers/storefront_provider.dart';
import '../storefront/core/storefront_renderer.dart';
import '../storefront/services/storefront_tracking_service.dart';
import '../theme/azaman_colors.dart';

class StorefrontScreen extends ConsumerStatefulWidget {
  final String businessProfileId;
  final String? businessName;

  const StorefrontScreen({
    super.key,
    required this.businessProfileId,
    this.businessName,
  });

  @override
  ConsumerState<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends ConsumerState<StorefrontScreen> {
  bool _viewTracked = false;

  @override
  void initState() {
    super.initState();
    // Fire storefront_view event on screen load (fire-and-forget)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_viewTracked) {
        StorefrontTrackingService.instance.trackEvent(
          widget.businessProfileId,
          'storefront_view',
          {'source': 'flutter_app'},
        );
        _viewTracked = true;
      }
    });
  }

  void _shareStorefront() {
    StorefrontTrackingService.instance.trackEvent(
      widget.businessProfileId,
      'share_click',
      {'widgetType': 'app_bar'},
    );
    // TODO: Replace with actual deep link URL once domain is configured
    final shareText = 'Check out ${widget.businessName ?? 'this business'} on AZAMAN!';
    Share.share(shareText);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AzamanColors.of(context);
    final renderAsync = ref.watch(storefrontRenderProvider(widget.businessProfileId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          widget.businessName ?? 'Storefront',
          style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.share, color: colors.textSecondary),
            onPressed: _shareStorefront,
          ),
        ],
      ),
      body: renderAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: colors.accent),
        ),
        error: (err, stack) => _ErrorState(
          error: err.toString(),
          onRetry: () => ref.invalidate(storefrontRenderProvider(widget.businessProfileId)),
          colors: colors,
        ),
        data: (response) {
          if (response == null) {
            return _NoStorefrontState(colors: colors);
          }

          return StorefrontRenderer(
            response: response,
            businessProfileId: widget.businessProfileId,
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final AzamanColors colors;

  const _ErrorState({required this.error, required this.onRetry, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text('Could not load storefront', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text(error, style: TextStyle(fontSize: 13, color: colors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onRetry, style: ElevatedButton.styleFrom(backgroundColor: colors.accent, foregroundColor: Colors.white), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _NoStorefrontState extends StatelessWidget {
  final AzamanColors colors;

  const _NoStorefrontState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 48, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text('No storefront published yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text('This business hasn\'t published their storefront. Check back later!', style: TextStyle(fontSize: 13, color: colors.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

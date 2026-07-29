// lib/screens/marketplace/saved_businesses_screen.dart
// =============================================================================
// Saved Businesses Screen — the user's wishlist.
// Shows all bookmarked businesses as BusinessCard(tall:false) tiles.
// Swipe-to-remove (Dismissible) lets them clean up the list.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/premium_glass_container.dart';
import 'package:azaman/widgets/animated_rating_stars.dart';

class SavedBusinessesScreen extends ConsumerStatefulWidget {
  const SavedBusinessesScreen({super.key});

  @override
  ConsumerState<SavedBusinessesScreen> createState() =>
      _SavedBusinessesScreenState();
}

class _SavedBusinessesScreenState
    extends ConsumerState<SavedBusinessesScreen> {
  final Map<String, BusinessProfile> _cache = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = ref.read(savedBusinessesProvider);
    if (saved.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final svc = BusinessService();
    for (final bizId in saved) {
      try {
        final b = await svc.getBusinessByBizId(bizId);
        if (b != null && mounted) {
          setState(() => _cache[bizId] = b);
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final saved = ref.watch(savedBusinessesProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          'Saved Businesses',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (saved.isNotEmpty)
            TextButton(
              onPressed: () {
                AzamanHaptics.toggle();
                ref.read(savedBusinessesProvider.notifier).clear();
              },
              child: Text('Clear all',
                  style: TextStyle(color: colors.textTertiary, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : saved.isEmpty
              ? const AzamanEmptyState(
                  icon: Icons.bookmark_outline,
                  title: 'No saved businesses',
                  subtitle: 'Tap the bookmark icon on any business to save it here.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.78),
                  itemCount: saved.length,
                  itemBuilder: (context, i) {
                    final bizId = saved.elementAt(i);
                    final b = _cache[bizId];
                    if (b == null) {
                      return Container(decoration: BoxDecoration(color: colors.softSurface, borderRadius: BorderRadius.circular(16)));
                    }
                    return Dismissible(
                      key: ValueKey(bizId), direction: DismissDirection.up,
                      background: Container(decoration: BoxDecoration(color: colors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                        child: const Align(alignment: Alignment.topCenter, child: Padding(padding: EdgeInsets.only(top: 12), child: Icon(Icons.delete_outline_rounded, color: Colors.red)))),
                      onDismissed: (_) {
                        AzamanHaptics.toggle();
                        ref.read(savedBusinessesProvider.notifier).remove(bizId);
                      },
                      child: GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BusinessProfileScreen(bizId: bizId))),
                        child: PremiumGlassContainer(
                          blur: 12, opacity: 0.04, borderRadius: 16, padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(flex: 3, child: Center(
                              child: b.logoUrl != null
                                ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(b.logoUrl!, fit: BoxFit.cover, width: double.infinity))
                                : Container(decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.1), shape: BoxShape.circle), padding: const EdgeInsets.all(16),
                                    child: Icon(Icons.storefront_outlined, size: 28, color: colors.accent)),
                            )),
                            const SizedBox(height: 8),
                            Text(b.businessName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Row(children: [AnimatedRatingStars(rating: b.averageRating, size: 10), const Spacer(), Icon(Icons.bookmark_rounded, size: 14, color: colors.accent)]),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

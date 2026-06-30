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
import 'package:azaman/widgets/business_card.dart';

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
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: saved.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final bizId = saved.elementAt(i);
                    final biz = _cache[bizId];
                    if (biz == null) {
                      return Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: colors.softSurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      );
                    }
                    return Dismissible(
                      key: Key(bizId),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) {
                        AzamanHaptics.toggle();
                        ref.read(savedBusinessesProvider.notifier).remove(bizId);
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: colors.danger,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete_forever_outlined,
                            color: Colors.white, size: 22),
                      ),
                      child: BusinessCard(
                        business: biz,
                        tall: false,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BusinessProfileScreen(bizId: bizId),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

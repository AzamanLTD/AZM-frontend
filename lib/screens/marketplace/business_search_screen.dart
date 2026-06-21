// =============================================================================
// BUSINESS SEARCH SCREEN — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Full-screen search experience: an autofocused search field, a category
// filter chip bar, and an infinite-scroll list of BusinessCard results.
// Debounced 400ms. Tapping a result opens its profile.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/widgets/azaman_empty_state.dart';
import 'package:azaman/widgets/business_card.dart';
import 'package:azaman/widgets/filter_chip_bar.dart';

class BusinessSearchScreen extends ConsumerStatefulWidget {
  const BusinessSearchScreen({super.key});

  @override
  ConsumerState<BusinessSearchScreen> createState() =>
      _BusinessSearchScreenState();
}

class _BusinessSearchScreenState extends ConsumerState<BusinessSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;
  int _categoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessSearchProvider.notifier).search('');
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(businessSearchProvider.notifier).loadMore();
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fire);
  }

  void _fire() {
    final cat = _categoryIndex == 0
        ? null
        : BusinessCategories.withAll[_categoryIndex].wire;
    ref
        .read(businessSearchProvider.notifier)
        .search(_searchCtrl.text.trim(), category: cat);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(businessSearchProvider);
    final labels = BusinessCategories.withAll.map((c) => c.label).toList();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: SizedBox(
          height: 40,
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: colors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search businesses, services…',
              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
              prefixIcon:
                  Icon(HugeIconsStroke.search01, size: 18, color: colors.textTertiary),
              filled: true,
              fillColor: colors.card,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          FilterChipBar(
            labels: labels,
            selectedIndex: _categoryIndex,
            onSelected: (i) {
              setState(() => _categoryIndex = i);
              _fire();
            },
          ),
          const SizedBox(height: 10),
          Expanded(child: _results(state, colors)),
        ],
      ),
    );
  }

  Widget _results(BusinessSearchState state, AzamanColors colors) {
    if (state.isLoading) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          height: 92,
          decoration: BoxDecoration(
            color: colors.softSurface,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }
    if (state.results.isEmpty) {
      return AzamanEmptyState(
        icon: HugeIconsSolid.store01,
        title: 'No businesses found',
        subtitle: 'Try a different search or category.',
      );
    }
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: state.results.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i >= state.results.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final biz = state.results[i];
        return BusinessCard(
          business: biz,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BusinessProfileScreen(bizId: biz.bizId),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// ROUTED TAB SURFACE  (Master Sprint v2, 2026-05-27)
//
// Several screens in the bottom-nav (TradesTabScreen, SavingsScreen, the
// FriendsHubScreen body) ship as tab bodies — they don't include a
// Scaffold or AppBar because the parent MainWrapper provides them. When
// we want to push one of them via Navigator (e.g. from a Today tile or a
// Quick Action), the user is left without a back button.
//
// This wrapper renders a transparent Scaffold + clean AppBar with a back
// button so any tab body can be pushed routed without changing its
// internals.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart' as theme_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoutedTabSurface extends ConsumerWidget {
  final String title;
  final Widget body;
  const RoutedTabSurface({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(theme_pkg.themeProvider).colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: body,
    );
  }
}

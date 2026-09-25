// =============================================================================
// SMART ROUTE LIST SCREEN  (Master Sprint, 2026-05-27)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/smart_route_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/smart_route/smart_route_create_screen.dart';
import 'package:azaman/widgets/smart_route/smart_route_card.dart';
import 'package:azaman/widgets/nav_transitions.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';


class SmartRouteListScreen extends ConsumerWidget {
  const SmartRouteListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final routesAsync = ref.watch(smartRoutesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Smart Routes',
          style: TextStyle(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: AzPullToRefresh(
        color: colors.accent,
        backgroundColor: colors.card,
        onRefresh: () => ref.read(smartRoutesProvider.notifier).refresh(),
        child: routesAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
          error: (e, _) => Center(child: Text(e.toString())),
          data: (routes) {
            if (routes.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.turn_left, size: 56, color: colors.textTertiary),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No smart routes yet',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Set-and-forget recurring transfers, MoMo payouts, savings, and vault deposits.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textTertiary, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: routes.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SmartRouteCard(route: routes[i], colors: colors)
                    .animate()
                    .fadeIn(delay: (i * 50).ms, duration: 280.ms)
                    .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          pushWithVerticalTransition(context, const SmartRouteCreateScreen());
        },
        backgroundColor: colors.accent,
        foregroundColor: colors.isDark ? Colors.black : Colors.white,
        icon: const Icon(Icons.add, size: 18),
        label: const Text(
          'New Route',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      ),
    );
  }
}

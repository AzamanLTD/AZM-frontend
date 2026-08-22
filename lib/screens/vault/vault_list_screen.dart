// =============================================================================
// VAULT LIST SCREEN  (Master Sprint, 2026-05-27)
//
// Slender, glass-forward grid of the user's vaults. Each card shows:
//   • Name + lock icon
//   • Circular progress ring (fraction of target)
//   • Streak chip + AZM-earned chip
//   • Maturity countdown
//
// Bottom CTA: "+ Create Vault" → vault_create_screen which gates behind
// the "Rules of the Game" sheet.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/vault_provider.dart';
import 'package:azaman/screens/vault/vault_create_screen.dart';
import 'package:azaman/screens/vault/vault_detail_screen.dart';
import 'package:azaman/screens/vault/shared_vault_screen.dart';
import 'package:azaman/widgets/vault/vault_progress_card.dart';
import 'package:azaman/widgets/nav_transitions.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';


class VaultListScreen extends ConsumerWidget {
  const VaultListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final vaultsAsync = ref.watch(vaultsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Vaults',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.groups, color: colors.textPrimary, size: 20),
            onPressed: () => pushWithVerticalTransition(context, const SharedVaultScreen()),
            tooltip: 'Shared Vaults',
          ),
        ],
      ),
      body: AzPullToRefresh(
        color: colors.accent,
        backgroundColor: colors.card,
        onRefresh: () => ref.read(vaultsProvider.notifier).refresh(),
        child: vaultsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
          error: (e, _) => _ErrorView(
            message: e.toString(),
            onRetry: () => ref.read(vaultsProvider.notifier).refresh(),
          ),
          data: (vaults) => _Body(vaults: vaults, colors: colors),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          pushWithVerticalTransition(context, const VaultCreateScreen());
        },
        backgroundColor: colors.accent,
        foregroundColor: colors.isDark ? Colors.black : Colors.white,
        icon: const Icon(Icons.add, size: 18),
        label: const Text(
          'Create Vault',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final List<Vault> vaults;
  final AzamanColors colors;
  const _Body({required this.vaults, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (vaults.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.lock_outline, size: 56, color: colors.textTertiary),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'No vaults yet',
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
                'Lock funds toward a goal. Earn AZM intensity rewards on every deposit.',
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
      itemCount: vaults.length,
      itemBuilder: (context, i) {
        final v = vaults[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: VaultProgressCard(vault: v, colors: colors, onTap: () {
            pushWithVerticalTransition(context, VaultDetailScreen(vaultId: v.id));
          })
              .animate()
              .fadeIn(delay: (i * 60).ms, duration: 280.ms)
              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_outlined, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

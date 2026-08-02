import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/card_skin_provider.dart';
import 'package:azaman/services/azm_spend_service.dart';
import 'package:azaman/widgets/peer_transfer_card.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class AzamanStoreScreen extends ConsumerStatefulWidget {
  const AzamanStoreScreen({super.key});

  @override
  ConsumerState<AzamanStoreScreen> createState() => _AzamanStoreScreenState();
}

class _AzamanStoreScreenState extends ConsumerState<AzamanStoreScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cardSkinProvider.notifier).primeIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final skinState = ref.watch(cardSkinProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.accent, colors.accent.withValues(alpha: 0.6)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.storefront_outlined, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              'AZAMAN STORE',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          if (skinState.catalog != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.diamond_outlined, size: 14, color: colors.accent),
                    const SizedBox(width: 4),
                    Text(
                      skinState.catalog!.azmBalance.toStringAsFixed(0),
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(cardSkinProvider.notifier).refresh(),
        color: colors.accent,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'CARD SKINS',
              style: TextStyle(color: colors.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Customize how your money transfers look in chat. Buy with AZM, equip anytime.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            _cardSkinSection(colors, skinState),
            const SizedBox(height: 32),
            _comingSoonSection(colors),
          ],
        ),
      ),
    );
  }

  // ── Card skins grid ──────────────────────────────────────────────────────

  Widget _cardSkinSection(AzamanColors colors, CardSkinState skinState) {
    if (skinState.loading && skinState.catalog == null) {
      return SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2.5)),
      );
    }

    final catalog = skinState.catalog;
    if (catalog == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: colors.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Couldn\'t load card skins. Pull to refresh.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12.5)),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: catalog.skins.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemBuilder: (context, i) {
        final skin = catalog.skins[i];
        final isEquipped = catalog.equippedCardSkin == skin.id;
        final isPending = skinState.pendingSkinId == skin.id;
        return _SkinTile(
          skin: skin,
          isEquipped: isEquipped,
          isPending: isPending,
          onTap: () => _handleTileTap(skin, isEquipped),
        ).animate().fadeIn(delay: (60 * i).ms, duration: 400.ms).slideY(begin: 0.08);
      },
    );
  }

  Future<void> _handleTileTap(CardSkinOption skin, bool isEquipped) async {
    if (isEquipped) return;
    final notifier = ref.read(cardSkinProvider.notifier);

    if (skin.owned) {
      AzamanHaptics.toggle();
      await notifier.equip(skin.id);
      final err = ref.read(cardSkinProvider).error;
      if (err != null && mounted) {
        _showSnack(err, isError: true);
      } else if (mounted) {
        _showSnack('Equipped "${skin.label}" — your next transfers will use it.');
      }
      return;
    }

    // Not owned — confirm purchase.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildPurchaseDialog(skin),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    final ok = await notifier.purchase(skin.id);
    if (!mounted) return;
    if (ok) {
      _showSnack('Purchased "${skin.label}"! Tap it again to equip.');
    } else {
      final err = ref.read(cardSkinProvider).error ?? 'Purchase failed.';
      _showSnack(err, isError: true);
    }
  }

  Widget _buildPurchaseDialog(CardSkinOption skin) {
    final colors = ref.read(themeProvider).colors;
    final def = resolveSkin(skin.id);
    return AlertDialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Buy "${skin.label}" skin?', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: def.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'This costs ${skin.cost.toStringAsFixed(0)} AZM and is a one-time purchase — you\'ll own it forever and can switch to it anytime.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: colors.textTertiary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Buy for ${skin.cost.toStringAsFixed(0)} AZM',
              style: TextStyle(color: colors.accent, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    final colors = ref.read(themeProvider).colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        backgroundColor: isError ? Colors.red.shade700 : colors.accent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Coming soon (unchanged) ──────────────────────────────────────────────

  Widget _comingSoonSection(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MORE COMING SOON',
            style: TextStyle(color: colors.accent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
          ),
          const SizedBox(height: 16),
          _expectItem(Icons.auto_awesome, 'Profile Decorations', 'Unique rings & badges', colors),
          const SizedBox(height: 12),
          _expectItem(Icons.palette_outlined, 'Design Your Own Skin', 'Spend AZM on a custom card design', colors),
          const SizedBox(height: 12),
          _expectItem(Icons.card_giftcard_outlined, 'Gift Cards', 'Send store items to friends', colors),
        ],
      ),
    );
  }

  Widget _expectItem(IconData icon, String title, String subtitle, dynamic colors) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: colors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(subtitle, style: TextStyle(color: colors.textTertiary, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Skin tile ────────────────────────────────────────────────────────────────

class _SkinTile extends StatelessWidget {
  final CardSkinOption skin;
  final bool isEquipped;
  final bool isPending;
  final VoidCallback onTap;

  const _SkinTile({
    required this.skin,
    required this.isEquipped,
    required this.isPending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final def = resolveSkin(skin.id);
    return GestureDetector(
      onTap: isPending ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: def.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          border: isEquipped ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: [
            BoxShadow(color: def.colors.last.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6)),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(def.label,
                    style: TextStyle(color: def.textColor, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  skin.owned ? (isEquipped ? 'Equipped' : 'Owned — tap to equip') : '${skin.cost.toStringAsFixed(0)} AZM',
                  style: TextStyle(color: def.textColor.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (isEquipped)
              Positioned(
                top: 0,
                right: 0,
                child: Icon(Icons.check_circle, color: def.textColor, size: 18),
              ),
            if (isPending)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(16)),
                  child: Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: def.textColor),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

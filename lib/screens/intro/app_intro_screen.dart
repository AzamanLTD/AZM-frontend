// =============================================================================
// AZAMAN — THE PUBLIC FIRST-LAUNCH INTRO (2026-10-28, priority P7)
//
// TWO SEPARATE ONBOARDING CONCEPTS, deliberately kept apart:
//
//   (A) THIS — the public intro. It runs BEFORE login, is about the product
//       ("what Azaman is"), and its only state is a LOCAL flag on the device
//       ([IntroStore]). Skipping it is allowed and NEVER claims the signed-in
//       setup is complete, because this screen cannot reach the server at all:
//       it has no API client and no auth dependency.
//
//   (B) The authenticated setup (/onboarding), keyed on the backend's
//       onboardingCompleted / onboardingStep. That one is not touched here.
//
// COPY RULES (owner): everything below must be true of the shipped product.
// No "bank-level security", no "guaranteed", no "100%" — the app holds money
// rails, and an unprovable absolute in a first-launch claim is a liability.
// GHS is the canonical currency and is described as such; the USDC rail is
// described as an approximate equivalent, never as a second native balance.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/router/route_registry.dart';
import 'package:azaman/services/intro_store.dart';
import 'package:azaman/screens/intro/intro_slide_art.dart';
import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/providers/theme_provider.dart';

/// One page of the public intro. `bodhi`-style: a short promise, a plain
/// sentence of what it means, and nothing that has to be taken on faith.
class IntroSlide {
  const IntroSlide({
    required this.headline,
    required this.body,
    required this.art,
  });

  final String headline;
  final String body;

  /// What the slide SHOWS. The artwork lives in [IntroSlideArt], built from
  /// real product components rather than a stand-in glyph.
  final IntroArt art;
}

const List<IntroSlide> kIntroSlides = <IntroSlide>[
  IntroSlide(
    art: IntroArt.wallet,
    headline: 'Your money, one card',
    body:
        'Your balance is held in Ghana cedis and shown exact. The ≈ USDC line '
        'beneath it is a conversion at the current rate, not a second '
        'account. '
        'The card above is an example.',
  ),
  IntroSlide(
    art: IntroArt.marketplace,
    headline: 'Shop, stay, eat, ride',
    body:
        'Everyday places in one marketplace. Each category carries its own '
        'colour, and every listing belongs to a business profile you can open '
        'before you commit.',
  ),
  IntroSlide(
    art: IntroArt.community,
    headline: 'Money inside the conversation',
    body:
        'Chat with the people you already know, save together in a Susu '
        'circle, and read every movement in one ledger instead of guessing.',
  ),
];

class AppIntroScreen extends ConsumerStatefulWidget {
  const AppIntroScreen({super.key, this.store});

  /// Injected for tests; production uses the device flag.
  final IntroStore? store;

  @override
  ConsumerState<AppIntroScreen> createState() => _AppIntroScreenState();
}

class _AppIntroScreenState extends ConsumerState<AppIntroScreen> {
  final PageController _pages = PageController();
  int _index = 0;
  bool _leaving = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Leaves the intro and records that it has been seen.
  ///
  /// The flag is LOCAL and only local: this is the public tour, so it must
  /// never stand in for the authenticated setup's completion state.
  Future<void> _leave({required bool skipped}) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await (widget.store ?? const IntroStore()).markSeen();
    if (!mounted) return;
    // The intro always hands off to sign-in: the user may already have a
    // session on this device, and the login screen forwards them onward.
    context.go(AzRoutes.login);
  }

  void _next() {
    if (_index >= kIntroSlides.length - 1) {
      _leave(skipped: false);
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The tour is the first surface a person sees, so it must look like the
    // app they are about to use: the SAVED appearance and the APPLIED card
    // variant, read from the local provider (no network, no auth). A fresh
    // install gets the product defaults because that is what the provider
    // holds — not because the tour hardcodes them.
    final theme = ref.watch(themeProvider);
    final colors = theme.colors;
    final variant = theme.cardVariant;
    final last = _index >= kIntroSlides.length - 1;
    return Scaffold(
      backgroundColor: colors.isDark
          ? kCardPalettes[variant]!.deep
          : colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                child: TextButton(
                  onPressed: _leaving ? null : () => _leave(skipped: true),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: kIntroSlides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _IntroPage(
                  slide: kIntroSlides[i],
                  colors: colors,
                  variant: variant,
                ),
              ),
            ),
            _Dots(count: kIntroSlides.length, index: _index, colors: colors),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _leaving ? null : _next,
                  style: FilledButton.styleFrom(
                    // The theme's own accent/on-accent pair: in dark the
                    // bright accent takes black ink, in light it takes white.
                    backgroundColor: colors.accent,
                    foregroundColor: colors.isDark
                        ? Colors.black
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.slide,
    required this.colors,
    required this.variant,
  });

  final IntroSlide slide;
  final AzamanColors colors;
  final BalanceCardVariant variant;

  @override
  Widget build(BuildContext context) {
    // Small phones and large text must SCROLL, not clip: the tour is the first
    // thing a new user ever sees, and an overflow stripe there is the worst
    // possible first impression. Content stays centred when it fits.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: IntroSlideArt(
                    art: slide.art,
                    colors: colors,
                    variant: variant,
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  slide.headline,
                  style: AzText.display.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 14),
                Text(
                  slide.body,
                  style: AzText.body.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.colors});

  final int count;
  final int index;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index
                  ? colors.accent
                  : colors.textSecondary.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// The slide anchors, drawn — a miniature of the real thing rather than a
/// decorative blob (the balance card, a storefront row, a transfer lane).

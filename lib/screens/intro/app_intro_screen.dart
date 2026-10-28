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
import 'package:go_router/go_router.dart';

import 'package:azaman/router/route_registry.dart';
import 'package:azaman/services/intro_store.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/providers/theme_provider.dart';

/// One page of the public intro. `bodhi`-style: a short promise, a plain
/// sentence of what it means, and nothing that has to be taken on faith.
class IntroSlide {
  const IntroSlide({
    required this.headline,
    required this.body,
    required this.marker,
  });

  final String headline;
  final String body;

  /// A simple glyph stand-in (drawn, not an emoji): the slide's anchor.
  final IntroMarker marker;
}

enum IntroMarker { balance, marketplace, transfer }

const List<IntroSlide> kIntroSlides = <IntroSlide>[
  IntroSlide(
    marker: IntroMarker.balance,
    headline: 'Your money, one card',
    body:
        'Your Azaman balance is held in Ghana cedis and shown exact. '
        'The USDC equivalent is marked ≈ because it is a conversion, '
        'not a second balance.',
  ),
  IntroSlide(
    marker: IntroMarker.marketplace,
    headline: 'Shop, stay, eat, ride',
    body:
        'A marketplace for everyday Ghana: stores, hotels, kitchens and '
        'transport in one place, each run by a verified business profile.',
  ),
  IntroSlide(
    marker: IntroMarker.transfer,
    headline: 'Send it in the chat',
    body:
        'Move money to the people you already talk to, keep savings groups '
        'together, and see every movement in one ledger you can read.',
  ),
];

class AppIntroScreen extends StatefulWidget {
  const AppIntroScreen({super.key, this.store});

  /// Injected for tests; production uses the device flag.
  final IntroStore? store;

  @override
  State<AppIntroScreen> createState() => _AppIntroScreenState();
}

class _AppIntroScreenState extends State<AppIntroScreen> {
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
    final colors = ThemeProvider.getColors(AzamanTheme.dark);
    final last = _index >= kIntroSlides.length - 1;
    return Scaffold(
      backgroundColor: kCardPalettes[BalanceCardVariant.blue]!.deep,
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
                itemBuilder: (context, i) =>
                    _IntroPage(slide: kIntroSlides[i], colors: colors),
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
  const _IntroPage({required this.slide, required this.colors});

  final IntroSlide slide;
  final AzamanColors colors;

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
                  child: SizedBox(
                    width: 168,
                    height: 104,
                    child: CustomPaint(
                      painter: IntroMarkerPainter(
                        marker: slide.marker,
                        palette: kCardPalettes[BalanceCardVariant.blue]!,
                      ),
                    ),
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
class IntroMarkerPainter extends CustomPainter {
  IntroMarkerPainter({required this.marker, required this.palette});

  final IntroMarker marker;
  final AzamanCardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bright, palette.deep],
        ).createShader(rect),
    );

    final white = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final faint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    switch (marker) {
      case IntroMarker.balance:
        // The chip, top right, and three ledger rules: a card face.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width - 44, size.height * 0.30, 26, 20),
            const Radius.circular(5),
          ),
          faint,
        );
        for (var i = 0; i < 3; i++) {
          final y = size.height * 0.62 + i * 9;
          canvas.drawLine(
            Offset(size.width * 0.16, y),
            Offset(size.width * (0.44 + i * 0.12), y),
            faint,
          );
        }
        canvas.drawLine(
          Offset(size.width * 0.16, size.height * 0.24),
          Offset(size.width * 0.42, size.height * 0.24),
          white,
        );
      case IntroMarker.marketplace:
        // Four storefront columns with awnings.
        final w = size.width * 0.14;
        for (var i = 0; i < 4; i++) {
          final x = size.width * 0.13 + i * (w + 6);
          canvas.drawRect(
            Rect.fromLTWH(x, size.height * 0.42, w, size.height * 0.40),
            faint,
          );
          canvas.drawLine(
            Offset(x - 1, size.height * 0.40),
            Offset(x + w + 1, size.height * 0.40),
            white,
          );
        }
      case IntroMarker.transfer:
        // Two rails converging on one dot: money moving between people.
        canvas.drawLine(
          Offset(size.width * 0.18, size.height * 0.34),
          Offset(size.width * 0.78, size.height * 0.62),
          faint,
        );
        canvas.drawLine(
          Offset(size.width * 0.18, size.height * 0.72),
          Offset(size.width * 0.78, size.height * 0.44),
          faint,
        );
        canvas.drawCircle(
          Offset(size.width * 0.80, size.height * 0.53),
          4.5,
          Paint()..color = Colors.white,
        );
        canvas.drawLine(
          Offset(size.width * 0.18, size.height * 0.53),
          Offset(size.width * 0.34, size.height * 0.53),
          white,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant IntroMarkerPainter oldDelegate) =>
      oldDelegate.marker != marker || oldDelegate.palette != palette;
}

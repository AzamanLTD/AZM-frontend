// =============================================================================
// ONBOARDING SCREEN — 3-page introduction flow for new users (V4)
//
// Architecture:
//   - ConsumerStatefulWidget with PageController for smooth transitions.
//   - Page 1: "Welcome to Azaman" — P2P trading intro.
//   - Page 2: "Secure & Fast" — Escrow protection & instant settlement.
//   - Page 3: "Start Trading" — Fund wallet & make first trade.
//   - On completion: PUT /api/users/onboarding/complete → MainNavigationWrapper.
//
// Theme-aware: all colors from `ref.watch(themeProvider).colors`.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/main.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();

  int _currentPage = 0;
  bool _isCompleting = false;

  static const List<_OnboardingPageData> _pages = [
    _OnboardingPageData(
      icon: Icons.swap_horiz_rounded,
      title: 'Welcome to Azaman',
      subtitle:
          'The fastest peer-to-peer trading platform. Buy and sell USDC directly with other users at the best rates — no middleman, no delays.',
    ),
    _OnboardingPageData(
      icon: Icons.shield_rounded,
      title: 'Secure & Fast',
      subtitle:
          'Every trade is protected by smart escrow. Funds are locked until both parties confirm — ensuring instant, trustless settlement every time.',
    ),
    _OnboardingPageData(
      icon: Icons.rocket_launch_rounded,
      title: 'Start Trading',
      subtitle:
          'Fund your wallet with crypto or fiat, browse live offers, and make your first trade in under 60 seconds. Welcome to the future of P2P.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);

    try {
      final response = await apiClient.post('/users/onboarding/complete', {});

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 204) {
        _navigateToMain();
      } else {
        // Still navigate — don't block the user on a non-critical endpoint
        _navigateToMain();
      }
    } catch (e) {
      // Network failure: still let user proceed
      if (mounted) _navigateToMain();
    }
  }

  void _navigateToMain() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigationWrapper()),
      (route) => false,
    );
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skip() {
    _completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: Skip button ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: _currentPage < _pages.length - 1
                    ? TextButton(
                        onPressed: _skip,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : const SizedBox(height: 36),
              ),
            ),

            // ── Page content ──────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) => _OnboardingPage(
                  data: _pages[index],
                  colors: colors,
                ),
              ),
            ),

            // ── Page indicator dots ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => _DotIndicator(
                    isActive: index == _currentPage,
                    colors: colors,
                  ),
                ),
              ),
            ),

            // ── Bottom action button ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isCompleting ? null : _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.isDark ? Colors.black : Colors.white,
                    disabledBackgroundColor: colors.accent.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isCompleting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colors.isDark ? Colors.black : Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          _currentPage == _pages.length - 1
                              ? 'Get Started'
                              : 'Next',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
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

// =============================================================================
// PAGE DATA MODEL
// =============================================================================
class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String subtitle;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

// =============================================================================
// SINGLE ONBOARDING PAGE — icon with glow + title + subtitle
// =============================================================================
class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;
  final AzamanColors colors;

  const _OnboardingPage({required this.data, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Icon with glow effect ─────────────────────────────────────
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accent.withOpacity(0.08),
              boxShadow: [
                BoxShadow(
                  color: colors.glow.withOpacity(0.2),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: colors.glow.withOpacity(0.1),
                  blurRadius: 80,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Icon(
              data.icon,
              size: 52,
              color: colors.accent,
            ),
          ),
          const SizedBox(height: 48),

          // ── Title ─────────────────────────────────────────────────────
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),

          // ── Subtitle ──────────────────────────────────────────────────
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.5,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DOT INDICATOR — animated active/inactive state
// =============================================================================
class _DotIndicator extends StatelessWidget {
  final bool isActive;
  final AzamanColors colors;

  const _DotIndicator({required this.isActive, required this.colors});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: isActive ? colors.accent : colors.textTertiary.withOpacity(0.3),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: colors.glow.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

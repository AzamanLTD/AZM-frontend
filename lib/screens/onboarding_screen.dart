// =============================================================================
// AZAMAN — Interactive Onboarding Screen (V2)
//
// Enhanced multi-step onboarding with:
//   • Animated feature showcase pages (3 intro slides)
//   • Interactive feature cards that respond to tap
//   • Personalized setup step: pick your primary use case
//   • Animated progress bar with smooth transitions
//   • Parallax hero images with glow effects
//   • Final "Get Started" with ripple effect
//
// Flow: 3 intro pages → setup page → complete onboarding → deposit prompt
// Reference: Robinhood onboarding, Cash App first-run, Revolut signup flow
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/main.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/deposit_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/nav_transitions.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCompleting = false;
  String? _selectedUseCase;

  static const _kTotalPages = 4; // 3 intro + 1 setup

  static const List<_OnboardingPageData> _pages = [
    _OnboardingPageData(
      icon: Icons.bolt_outlined,
      imagePath: "assets/images/1.webp",
      title: "Ghana's Fastest P2P Platform",
      subtitle: "Buy and sell USDC instantly via MTN MoMo, Telecel or AirtelTigo. "
        "No bank account needed — just your phone number.",
      features: ['Instant MoMo settlement', 'Zero gas fees', '24/7 marketplace'],
    ),
    _OnboardingPageData(
      icon: Icons.shield_outlined,
      imagePath: "assets/images/2.webp",
      title: "Every Trade is Escrow-Protected",
      subtitle: "Funds are locked in smart escrow until both parties confirm. "
        "No fraud, no chargebacks — just safe, instant settlement.",
      features: ['Smart escrow locking', 'Dispute resolution', 'Anti-fraud protection'],
    ),
    _OnboardingPageData(
      icon: Icons.group_outlined,
      imagePath: "assets/images/3.webp",
      title: "Grow With Your Community",
      subtitle: "Join a Susu circle with friends and family. "
        "Contribute together, collect in turns — the traditional way, "
        "powered by modern fintech.",
      features: ['Susu savings circles', 'Community trust scores', 'Shared vaults'],
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
      await apiClient.post('/users/onboarding/complete', {
        'primaryUseCase': _selectedUseCase,
      });
      if (!mounted) return;
      _navigateToMain();
    } catch (_) {
      if (mounted) _navigateToMain();
    }
  }

  void _navigateToMain() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainNavigationWrapper()),
      (route) => false,
    );
    Future.delayed(const Duration(milliseconds: 700), () {
      if (context.mounted) {
        pushWithVerticalTransition(context, const DepositScreen(initialTab: DepositTab.fiat));
      }
    });
  }

  void _nextPage() {
    if (_currentPage < _kTotalPages - 1) {
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
            // ── Top bar: progress bar + skip ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (_currentPage + 1) / _kTotalPages,
                        backgroundColor: colors.divider,
                        valueColor: AlwaysStoppedAnimation(colors.accent),
                        minHeight: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_currentPage < _kTotalPages - 1)
                    TextButton(
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
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),

            // ── Page content ──
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _kTotalPages,
                onPageChanged: (index) => setState(() => _currentPage = index),
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  if (index < 3) {
                    return _OnboardingPage(
                      data: _pages[index],
                      colors: colors,
                      isActive: index == _currentPage,
                    );
                  }
                  return _SetupPage(
                    colors: colors,
                    selectedUseCase: _selectedUseCase,
                    onSelect: (v) => setState(() => _selectedUseCase = v),
                  );
                },
              ),
            ),

            // ── Page indicator dots ──
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _kTotalPages,
                  (index) => _DotIndicator(
                    isActive: index == _currentPage,
                    colors: colors,
                  ),
                ),
              ),
            ),

            // ── Bottom action button ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isCompleting || (_currentPage == _kTotalPages - 1 && _selectedUseCase == null)
                      ? null
                      : _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.isDark ? Colors.black : Colors.white,
                    disabledBackgroundColor: colors.accent.withValues(alpha: 0.3),
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
                          _currentPage == _kTotalPages - 1
                              ? 'Get Started'
                              : 'Continue',
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
  final String? imagePath;
  final List<String> features;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.imagePath,
    this.features = const [],
  });
}

// =============================================================================
// SINGLE ONBOARDING PAGE — hero image with glow + title + subtitle + features
// =============================================================================
class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;
  final AzamanColors colors;
  final bool isActive;

  const _OnboardingPage({
    required this.data,
    required this.colors,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Hero image or icon with glow ──
          Expanded(
            child: data.imagePath != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    data.imagePath!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                )
              : Center(
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accent.withValues(alpha: 0.08),
                      boxShadow: [
                        BoxShadow(
                          color: colors.glow.withValues(alpha: 0.2),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: colors.glow.withValues(alpha: 0.1),
                          blurRadius: 80,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(data.icon, size: 52, color: colors.accent),
                  ),
                ),
          ),
          const SizedBox(height: 36),

          // ── Title ──
          if (isActive)
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
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1)
          else
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
          const SizedBox(height: 14),

          // ── Subtitle ──
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
          const SizedBox(height: 24),

          // ── Feature chips ──
          if (data.features.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: data.features.map((f) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.accent.withValues(alpha: 0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: colors.accent),
                    const SizedBox(width: 5),
                    Text(
                      f,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// SETUP PAGE — pick your primary use case
// =============================================================================
class _SetupPage extends StatelessWidget {
  final AzamanColors colors;
  final String? selectedUseCase;
  final ValueChanged<String> onSelect;

  const _SetupPage({
    required this.colors,
    required this.selectedUseCase,
    required this.onSelect,
  });

  static const _useCases = [
    _UseCase(icon: Icons.swap_horiz, label: 'P2P Trading', desc: 'Buy & sell USDC'),
    _UseCase(icon: Icons.savings, label: 'Susu Savings', desc: 'Join savings circles'),
    _UseCase(icon: Icons.send, label: 'Remittances', desc: 'Send money home'),
    _UseCase(icon: Icons.storefront, label: 'Business', desc: 'Accept payments'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.waving_hand, size: 48, color: colors.accent)
              .animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 16),
          Text(
            'What brings you here?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 8),
          Text(
            'We\'ll personalize your experience',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 36),
          ..._useCases.map((uc) {
            final isSelected = selectedUseCase == uc.label;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelect(uc.label);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.accent.withValues(alpha: 0.1)
                        : colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? colors.accent.withValues(alpha: 0.4)
                          : colors.divider,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.accent.withValues(alpha: 0.15)
                              : colors.divider,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          uc.icon,
                          color: isSelected ? colors.accent : colors.textSecondary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              uc.label,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              uc.desc,
                              style: TextStyle(
                                color: colors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: isSelected
                            ? Icon(Icons.check_circle, key: const ValueKey('check'), color: colors.accent, size: 24)
                            : Icon(Icons.circle_outlined, key: const ValueKey('empty'), color: colors.divider, size: 24),
                      ),
                    ],
                  ),
                ),
              ),
            ).animate().fadeIn(delay: Duration(milliseconds: 300 + _useCases.indexOf(uc) * 80));
          }),
        ],
      ),
    );
  }
}

class _UseCase {
  final IconData icon;
  final String label;
  final String desc;

  const _UseCase({required this.icon, required this.label, required this.desc});
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
        color: isActive ? colors.accent : colors.textTertiary.withValues(alpha: 0.3),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: colors.glow.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

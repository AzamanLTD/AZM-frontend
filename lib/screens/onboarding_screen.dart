// =============================================================================
// AZAMAN — AUTHENTICATED ACCOUNT SETUP
//
// This is NOT the tour. The public tour (lib/screens/intro/) introduces Azaman
// to someone who has never seen it, before login. This screen runs once the
// account exists and asks the one thing the server actually needs at this
// stage: what the person is mainly here to do.
//
// It replaced a four-page feature showcase that replayed the tour's promise
// after registration, with artwork from assets/images/1-3.webp and claims the
// product cannot support ("Ghana's Fastest P2P Platform", "Zero gas fees",
// "no fraud, no chargebacks"). A first-use journey cannot borrow credibility
// from a better tour elsewhere; the claims are gone with the pages.
//
// Contract preserved exactly as it was:
//   POST /users/onboarding/complete { primaryUseCase }
//   • success  → primary-phone verification (AzRoutes.verifyPhone);
//   • failure  → stay here, say so, offer retry. A failed completion call is
//                never treated as a completed setup.
//   • 'Later' posts the same call with a null use case, which is what the old
//     Skip button did: the field is useful, not a gate.
//
// Not here, deliberately: no deposit prompt, no KYC at first login, no
// permissions. Phone verification follows on its own screen, and contacts and
// location are offered there as separate optional choices.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' show GoRouterHelper;

import 'package:azaman/router/route_registry.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String? _selectedUseCase;
  bool _isCompleting = false;

  static const List<_UseCase> _useCases = <_UseCase>[
    _UseCase(
      icon: Icons.swap_horiz,
      label: 'P2P trading',
      desc: 'Buy and sell USDC',
    ),
    _UseCase(
      icon: Icons.savings_outlined,
      label: 'Susu savings',
      desc: 'Save with a circle',
    ),
    _UseCase(
      icon: Icons.send_outlined,
      label: 'Remittances',
      desc: 'Send money home',
    ),
    _UseCase(
      icon: Icons.storefront_outlined,
      label: 'Business',
      desc: 'Take payments',
    ),
  ];

  Future<void> _completeOnboarding({String? useCase}) async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);

    try {
      // The injected client, not the global singleton: same request, but the
      // completion contract is reachable from a test without a live server.
      await ref.read(apiClientProvider).post('/users/onboarding/complete', {
        'primaryUseCase': useCase,
      });
      if (!mounted) return;
      _goToPhoneStep();
    } catch (_) {
      // A failed completion call is NOT a completed setup. Telling the person
      // they are set up when the server never heard about it is the defect
      // this branch exists to remove.
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Could not save your setup. Check your connection.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _completeOnboarding(useCase: useCase),
          ),
        ),
      );
    }
  }

  /// After setup the next real step is the phone number, not a deposit form.
  void _goToPhoneStep() => context.go(AzRoutes.verifyPhone);

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 56,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set up your account',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'What will you mostly use Azaman for? This decides what we '
                    'show you first. You can change it later.',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  for (final useCase in _useCases) ...[
                    _UseCaseTile(
                      useCase: useCase,
                      colors: colors,
                      selected: _selectedUseCase == useCase.label,
                      onTap: _isCompleting
                          ? null
                          : () => setState(
                              () => _selectedUseCase = useCase.label,
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isCompleting || _selectedUseCase == null
                          ? null
                          : () =>
                                _completeOnboarding(useCase: _selectedUseCase),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: colors.isDark
                            ? Colors.black
                            : Colors.white,
                        disabledBackgroundColor: colors.accent.withValues(
                          alpha: 0.3,
                        ),
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
                          : const Text(
                              'Continue',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _isCompleting
                          ? null
                          : () => _completeOnboarding(),
                      child: Text(
                        'Decide later',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Next: confirm your phone number.',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UseCaseTile extends StatelessWidget {
  const _UseCaseTile({
    required this.useCase,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final _UseCase useCase;
  final AzamanColors colors;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? colors.accent.withValues(alpha: 0.10)
                : colors.softSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.accent : colors.divider,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                useCase.icon,
                size: 22,
                color: selected ? colors.accent : colors.textSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      useCase.label,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      useCase.desc,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 20, color: colors.accent),
            ],
          ),
        ),
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

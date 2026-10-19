// =============================================================================
// HELP & FAQ — the Support surface for the settings redesign (2026-10-16).
//
// Design contract (Phantom-inspired settings refresh):
//   • icon-first, sentence case, no ALL-CAPS enterprise labels;
//   • real answers only — every FAQ below documents behaviour that exists
//     in the codebase (STK-push MoMo deposits, payout destinations, KYC
//     tiers, AZM ID, P2P escrow, biometric lock);
//   • NO invented contact channels: when Azaman's official support email /
//     WhatsApp number is decided, a "Contact us" row slots in under the
//     FAQ with a one-line wiring change. Until then this screen stays
//     honest — it never shows a fake email or number.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class _FaqItem {
  final IconData icon;
  final String question;
  final String answer;
  const _FaqItem(this.icon, this.question, this.answer);
}

const _faq = <_FaqItem>[
  _FaqItem(
    Icons.arrow_downward,
    'How do deposits work?',
    'Add a MoMo number under Money, then start a deposit. Azaman sends an '
        'STK push to that number; approve it on your phone and the funds '
        'settle to your balance once confirmed.',
  ),
  _FaqItem(
    Icons.arrow_outward,
    'Where do withdrawals arrive?',
    'Withdrawals go to a saved payout destination. Payout destinations '
        'live under Money in Settings, saved either as MoMo or as a crypto '
        'wallet address.',
  ),
  _FaqItem(
    Icons.verified_user_outlined,
    'What does verification (KYC) do?',
    'Verifying confirms your identity with our KYC provider. Start from '
        'Account, then Identity Verification; your status shows on your '
        'profile. Withdrawals arrive at payout destinations you verify '
        'yourself under Money, Accounts.',
  ),
  _FaqItem(
    Icons.badge_outlined,
    'What is my AZM ID?',
    'Your AZM ID is your public Azaman identity, like AZM-000123456. '
        'Share it instead of bank details: people can send to it and find '
        'your profile. It never reveals your balance.',
  ),
  _FaqItem(
    Icons.swap_horiz,
    'How does a P2P trade stay safe?',
    'Every trade is held in escrow. The seller\'s crypto is locked as '
        'soon as the trade is accepted; it only releases when you confirm '
        'your payment. If anything goes wrong, open a dispute before you '
        'confirm.',
  ),
  _FaqItem(
    Icons.lock_outline,
    'How do I protect my account?',
    'Turn on the biometric lock under Security so sensitive actions ask '
        'for your fingerprint or face, and keep two-factor sign-in on. '
        'You can review recent sign-ins under Account Activity.',
  ),
];

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeProvider.getColors(
      Theme.of(context).brightness == Brightness.dark
          ? AzamanTheme.dark
          : AzamanTheme.light,
    );

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Help & FAQ',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _faq.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(
                left: 4,
                bottom: 12,
              ),
              child: Text(
                'Quick answers to the everyday questions.',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 13,
                ),
              ),
            );
          }
          final item = _faq[index - 1];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider),
            ),
            child: ExpansionTile(
              initiallyExpanded: index == 1,
              tilePadding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              shape: const Border(),
              iconColor: colors.textTertiary,
              collapsedIconColor: colors.textTertiary,
              onExpansionChanged: (_) => AzamanHaptics.toggle(),
              title: Row(
                children: [
                  Icon(item.icon, color: colors.accent, size: 19),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.question,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 31),
                  child: Text(
                    item.answer,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

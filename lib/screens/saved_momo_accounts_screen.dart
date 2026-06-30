// =============================================================================
// SAVED MOMO ACCOUNTS SCREEN  (Master Sprint v2, 2026-05-27)
//
// Address book of pre-saved mobile-money numbers the user uses to receive
// deposit prompts. Each entry shows:
//   • Provider chip (MTN / Vodafone / Telecel)
//   • Nickname + verified registered name
//   • E.164 phone number
//   • Primary star
//
// Add flow is a 2-step bottom sheet: lookup → confirm + password gate.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';


class SavedMomoAccountsScreen extends ConsumerWidget {
  const SavedMomoAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final accountsAsync = ref.watch(savedMomoProvider);

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
          'Deposit Addresses',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: colors.accent,
        backgroundColor: colors.card,
        onRefresh: () => ref.read(savedMomoProvider.notifier).refresh(),
        child: accountsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
          error: (e, _) => Center(child: Text(e.toString())),
          data: (accounts) {
            if (accounts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.smartphone_outlined, size: 48, color: colors.textTertiary),
                    const SizedBox(height: 12),
                    Text(
                      'No deposit addresses yet',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "+ Add Account" to save one.',
                      style: TextStyle(color: colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: accounts.asMap().entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _MomoTile(account: e.value, colors: colors)
                              .animate()
                              .fadeIn(delay: (e.key * 50).ms, duration: 280.ms)
                              .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
                        ),
                      ).toList(),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 0,
        onPressed: () {
          HapticFeedback.lightImpact();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const AddMomoAccountSheet(),
          );
        },
        backgroundColor: colors.accent,
        foregroundColor: colors.isDark ? Colors.black : Colors.white,
        icon: const Icon(Icons.add, size: 18),
        label: const Text(
          'Add Account',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      ),
    );
  }
}

class _MomoTile extends ConsumerWidget {
  final SavedMomoAccount account;
  final AzamanColors colors;
  const _MomoTile({required this.account, required this.colors});

  Color _providerColor() => switch (account.provider) {
        'MTN' => const Color(0xFFFFCC00),
        'VODAFONE' => const Color(0xFFE60000),
        'TELECEL' => const Color(0xFF0066CC),
        _ => colors.textSecondary,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pcolor = _providerColor();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.card.withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider, width: 0.7),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: pcolor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.smartphone_outlined, color: pcolor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      account.nickname,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (account.isPrimary) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.star_outline, color: colors.warning, size: 12),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${account.provider} · ${account.phoneNumber}',
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
                if (account.accountName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Verified: ${account.accountName}',
                    style: TextStyle(color: colors.success, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.danger.withOpacity(0.8), size: 18),
            onPressed: () async {
              HapticFeedback.mediumImpact();
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: colors.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text('Delete account?', style: TextStyle(color: colors.textPrimary)),
                  content: Text('Remove "${account.nickname}" from your saved deposit addresses?',
                      style: TextStyle(color: colors.textSecondary)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('Delete', style: TextStyle(color: colors.danger)),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                await ref.read(savedMomoProvider.notifier).delete(account.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ADD MOMO ACCOUNT SHEET — 2-step flow (lookup name → confirm + password)
// =============================================================================
class AddMomoAccountSheet extends ConsumerStatefulWidget {
  const AddMomoAccountSheet({super.key});

  @override
  ConsumerState<AddMomoAccountSheet> createState() => _AddMomoAccountSheetState();
}

class _AddMomoAccountSheetState extends ConsumerState<AddMomoAccountSheet> {
  final _nickname = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _provider = 'MTN';
  String? _verifiedName;
  String? _msisdn;
  bool _busy = false;
  bool _markPrimary = false;

  @override
  void dispose() {
    _nickname.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    if (_phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a phone number to look up.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ref.read(savedMomoProvider.notifier).lookupName(
            provider: _provider,
            phoneNumber: _phone.text.trim(),
          );
      setState(() {
        _verifiedName = res.name;
        _msisdn = res.msisdn;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_verifiedName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Look up the name first.')),
      );
      return;
    }
    if (_password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confirm with your password.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(savedMomoProvider.notifier).create(
            nickname: _nickname.text.trim().isEmpty
                ? '${_provider} ${_msisdn ?? _phone.text.trim()}'
                : _nickname.text.trim(),
            provider: _provider,
            phoneNumber: _msisdn ?? _phone.text.trim(),
            password: _password.text,
            isPrimary: _markPrimary,
          );
      if (mounted) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: colors.glow.withOpacity(0.18))),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Add Deposit Address',
                style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              "We'll verify the registered name on the number before you save it.",
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _label(colors, 'Network Provider'),
            Wrap(
              spacing: 6,
              children: ['MTN', 'VODAFONE', 'TELECEL']
                  .map((p) => ChoiceChip(
                        selected: _provider == p,
                        label: Text(p),
                        selectedColor: colors.accent.withOpacity(0.20),
                        onSelected: (_) => setState(() {
                          _provider = p;
                          _verifiedName = null;
                        }),
                        labelStyle: TextStyle(
                          color: _provider == p ? colors.accent : colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            _label(colors, 'Phone Number'),
            Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.divider),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '0541234567 or +233541234567',
                        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12.5),
                      ),
                      onChanged: (_) {
                        if (_verifiedName != null) {
                          setState(() => _verifiedName = null);
                        }
                      },
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _lookup,
                    child: Text(_busy ? '…' : 'Verify',
                        style: TextStyle(color: colors.accent, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            if (_verifiedName != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.success.withOpacity(0.30)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: colors.success, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Registered to: $_verifiedName',
                        style: TextStyle(
                          color: colors.success,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _label(colors, 'Nickname (optional)'),
            Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.divider),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _nickname,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'e.g. My MTN Wallet',
                  hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            CheckboxListTile.adaptive(
              value: _markPrimary,
              onChanged: (v) => setState(() => _markPrimary = v ?? false),
              contentPadding: EdgeInsets.zero,
              activeColor: colors.accent,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('Set as primary',
                  style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.warning.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.warning.withOpacity(0.20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: colors.warning, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Confirm with your password to save.',
                      style: TextStyle(color: colors.warning, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.divider),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _password,
                obscureText: true,
                style: TextStyle(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Password',
                  hintStyle: TextStyle(color: colors.textTertiary, fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy || _verifiedName == null ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.isDark ? Colors.black : Colors.white,
                  disabledBackgroundColor: colors.accent.withOpacity(0.30),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  _busy ? 'Saving…' : 'Save Account',
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(AzamanColors colors, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          s.toUpperCase(),
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/saved_momo_provider.dart';
import 'package:azaman/providers/theme_provider.dart';


class AddMomoAccountSheet extends ConsumerStatefulWidget {
  const AddMomoAccountSheet({super.key});

  @override
  ConsumerState<AddMomoAccountSheet> createState() =>
      _AddMomoAccountSheetState();
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
      final res = await ref
          .read(savedMomoProvider.notifier)
          .lookupName(provider: _provider, phoneNumber: _phone.text.trim());
      setState(() {
        _verifiedName = res.name;
        _msisdn = res.msisdn;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_verifiedName == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Look up the name first.')));
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
      final account = await ref
          .read(savedMomoProvider.notifier)
          .create(
            nickname: _nickname.text.trim().isEmpty
                ? '$_provider ${_msisdn ?? _phone.text.trim()}'
                : _nickname.text.trim(),
            provider: _provider,
            phoneNumber: _msisdn ?? _phone.text.trim(),
            password: _password.text,
            isPrimary: _markPrimary,
          );
      if (mounted) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context, account);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: colors.glow.withValues(alpha: 0.18)),
        ),
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
            Text(
              'Add Deposit Address',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "We'll verify the registered name on the number before you save it.",
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _label(colors, 'Network Provider'),
            Wrap(
              spacing: 6,
              children: ['MTN', 'TELECEL', 'AIRTELTIGO']
                  .map(
                    (provider) => ChoiceChip(
                      selected: _provider == provider,
                      label: Text(provider),
                      selectedColor: colors.accent.withValues(alpha: 0.20),
                      onSelected: (_) => setState(() {
                        _provider = provider;
                        _verifiedName = null;
                      }),
                      labelStyle: TextStyle(
                        color: _provider == provider
                            ? colors.accent
                            : colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            _label(colors, 'Phone Number'),
            _FieldShell(
              colors: colors,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '0541234567 or +233541234567',
                        hintStyle: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12.5,
                        ),
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
                    child: Text(
                      _busy ? '...' : 'Verify',
                      style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_verifiedName != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colors.success.withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: colors.success,
                      size: 16,
                    ),
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
            _FieldShell(
              colors: colors,
              child: TextField(
                controller: _nickname,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'e.g. My MTN Wallet',
                  hintStyle: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            CheckboxListTile.adaptive(
              value: _markPrimary,
              onChanged: (value) =>
                  setState(() => _markPrimary = value ?? false),
              contentPadding: EdgeInsets.zero,
              activeColor: colors.accent,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Set as primary',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colors.warning.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: colors.warning, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Confirm with your password to save.',
                      style: TextStyle(
                        color: colors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _FieldShell(
              colors: colors,
              child: TextField(
                controller: _password,
                obscureText: true,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Password',
                  hintStyle: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 12.5,
                  ),
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
                  disabledBackgroundColor: colors.accent.withValues(
                    alpha: 0.30,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _busy ? 'Saving...' : 'Save Account',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(AzamanColors colors, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _FieldShell extends StatelessWidget {
  final AzamanColors colors;
  final Widget child;

  const _FieldShell({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: child,
    );
  }
}

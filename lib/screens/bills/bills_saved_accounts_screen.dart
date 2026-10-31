// AZAMAN — ACCOUNTS · SAVED BILL ACCOUNTS
//
// The Accounts screen's third category. It is a VIEW over the Bills saved-account
// contract (GET/PATCH/DELETE /bills/saved-accounts) through the existing Bills
// gateway — never a MoMo/wallet account, and deliberately not the Bills hub:
// there is no "find a biller" rail here, because this is the member's saved
// references, not discovery.
//
// What may be shown: the service label, the category, the member's nickname,
// the SERVER's mask, the primary flag and the server's verification status.
// What may never be shown: the reference in plaintext, any ciphertext or
// fingerprint, or a holder name the provider never returned.
//
// There is no Pay action. Paying a bill is a money action and lives in the Bills
// hub behind its own guard; a reference list is not a payment surface.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/bills/bills_home_screen.dart';
import 'package:azaman/services/bills/bills_gateway.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/bills/bills_ui.dart';
import 'package:azaman/widgets/home/money_lock_surface.dart';
import 'package:azaman/widgets/nav_transitions.dart';

class BillsSavedAccountsScreen extends ConsumerWidget {
  const BillsSavedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

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
          'Saved bills',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      // A saved bill reference is private money data: while the app is locked
      // the list is not built at all, so no mask reaches the widget tree or the
      // accessibility tree.
      body: MoneyLockGate(
        message: 'Unlock to see your saved bills',
        child: _SavedBillsBody(
          colors: colors,
          onDiscover: () =>
              pushWithVerticalTransition(context, const BillsHomeScreen()),
        ),
      ),
    );
  }
}

class _SavedBillsBody extends ConsumerStatefulWidget {
  const _SavedBillsBody({required this.colors, required this.onDiscover});

  final AzamanColors colors;
  final VoidCallback onDiscover;

  @override
  ConsumerState<_SavedBillsBody> createState() => _SavedBillsBodyState();
}

class _SavedBillsBodyState extends ConsumerState<_SavedBillsBody> {
  /// Rename, primary and delete against the routes the backend publishes.
  ///
  /// The list is refetched from the server afterwards rather than patched in
  /// memory: the member should see what was saved, not what was hoped for.
  Future<void> _manage(SavedBillAccount account, String choice) async {
    final gateway = ref.read(billsGatewayProvider);
    try {
      switch (choice) {
        case 'rename':
          final name = await _askName(account);
          if (name == null || !mounted) return;
          await gateway.updateAccount(accountId: account.id, alias: name);
          break;
        case 'primary':
          await gateway.updateAccount(
            accountId: account.id,
            isPrimary: !account.isPrimary,
          );
          break;
        case 'delete':
          final confirmed = await _confirmDelete(account);
          if (confirmed != true) return;
          await gateway.removeAccount(account.id);
          break;
      }
      ref.invalidate(savedBillAccountsProvider);
      ref.invalidate(billsHubProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is BillsUnavailableException
                ? (e.message ?? 'That change was not saved.')
                : "We couldn't save that change just now.",
          ),
        ),
      );
    }
  }

  Future<String?> _askName(SavedBillAccount account) async {
    final controller = TextEditingController(text: account.alias ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this bill'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            hintText: 'My Apartment',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<bool?> _confirmDelete(SavedBillAccount account) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove this bill?'),
      content: Text(
        '${account.displayName} stops appearing here. Nothing is paid or '
        'cancelled, and you can save it again later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep it'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final accounts = ref.watch(savedBillAccountsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(savedBillAccountsProvider);
        await ref.read(savedBillAccountsProvider.future);
      },
      child: accounts.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        // An unavailable list is stated, never rendered as an empty one: "you
        // have no saved bills" would be a claim about the member's data.
        error: (_, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: const [
            BillsEmptyNote(
              icon: Icons.cloud_off_outlined,
              text:
                  'Saved bills are unavailable right now. That is not the same '
                  'as having none — pull down to try again.',
            ),
          ],
        ),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const BillsEmptyNote(
                  icon: Icons.receipt_long_outlined,
                  text:
                      'No saved bills yet. Save a service reference — a meter '
                      'or smartcard number — and it lives here, marked '
                      'unverified until a provider can confirm it.',
                ),
                const SizedBox(height: 16),
                BillsPrimaryButton(
                  label: 'Find a biller',
                  onPressed: widget.onDiscover,
                ),
              ],
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              for (final account in list) ...[
                BillsAccountTile(
                  title: account.displayName,
                  subtitle: account.isPrimary
                      ? '${account.billerName} · Primary'
                      : '${account.billerName} · ${account.categoryId}',
                  maskedIdentifier: account.identifierMasked,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (account.verificationStatus == 'UNVERIFIED')
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            'Unverified',
                            style: AzText.caption.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                      PopupMenuButton<String>(
                        key: ValueKey('saved-bill-actions-${account.id}'),
                        tooltip: 'Manage ${account.displayName}',
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: colors.textTertiary,
                        ),
                        onSelected: (choice) => _manage(account, choice),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                          PopupMenuItem(
                            value: 'primary',
                            child: Text(
                              account.isPrimary
                                  ? 'Remove primary'
                                  : 'Make primary',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Remove this bill'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'References are masked here. Paying or requesting a bill '
                  'happens in Bills.',
                  textAlign: TextAlign.center,
                  style: AzText.caption.copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

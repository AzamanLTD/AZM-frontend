// lib/screens/trade_accounts_screen.dart
// =============================================================================
// AZAMAN V2 — TRADE ACCOUNTS MANAGEMENT SCREEN (Phase F2-FE)
//
// Full CRUD for the 11 supported global payment method types. Vendors register
// accounts here, submit for admin verification, and later link them to ads.
// Regular buyers can also manage their payment details for SELL-ad trades.
//
// Reachable from:
//   - settings_screen.dart → "Trade Accounts" tile (Payment section)
//   - vendor_dashboard.dart → "Manage Accounts" link
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/trade_account_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/trade_account_service.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';


class TradeAccountsScreen extends ConsumerStatefulWidget {
  const TradeAccountsScreen({super.key});

  @override
  ConsumerState<TradeAccountsScreen> createState() =>
      _TradeAccountsScreenState();
}

class _TradeAccountsScreenState extends ConsumerState<TradeAccountsScreen> {
  @override
  void initState() {
    super.initState();
    // Prime the provider on first visit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tradeAccountProvider.notifier).primeIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final accountState = ref.watch(tradeAccountProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Trade Accounts',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (accountState.isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accent,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: AzPullToRefresh(
        color: colors.accent,
        onRefresh: () => ref.read(tradeAccountProvider.notifier).refresh(),
        child: accountState.isLoading && accountState.accounts.isEmpty
            ? _buildSkeleton(colors)
            : accountState.accounts.isEmpty
                ? _buildEmpty(colors)
                : _buildAccountList(accountState.accounts, colors),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add Account',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          HapticFeedback.selectionClick();
          _showAddAccountSheet(colors);
        },
      ),
    );
  }

  // ── List View ─────────────────────────────────────────────────────────────

  Widget _buildAccountList(List<TradeAccount> accounts, AzamanColors colors) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: accounts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildAccountTile(accounts[i], colors),
    );
  }

  Widget _buildAccountTile(TradeAccount account, AzamanColors colors) {
    final statusColor = account.isApproved
        ? colors.success
        : account.isPending
            ? colors.warning
            : colors.danger;
    final statusText = account.isApproved
        ? 'APPROVED'
        : account.isPending
            ? 'PENDING'
            : 'REJECTED';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          // Method icon
          CircleAvatar(
            radius: 22,
            backgroundColor: colors.accent.withValues(alpha: 0.12),
            child: Icon(
              _iconForMethod(account.methodType),
              color: colors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        SupportedMethod.displayName(account.methodType),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  account.displayLabel,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Delete button
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.danger, size: 20),
            onPressed: () => _confirmDelete(account, colors),
          ),
        ],
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmpty(AzamanColors colors) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.account_balance_wallet_outlined,
            size: 56, color: colors.textTertiary),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'No Trade Accounts',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Add your Zelle, CashApp, Venmo, or other\npayment methods for P2P trading.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              children: [
                Icon(Icons.info_outline, color: colors.accent, size: 20),
                const SizedBox(height: 8),
                Text(
                  'Accounts require admin approval before\nthey can be linked to your P2P ads.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _buildSkeleton(AzamanColors colors) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 72,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
      ),
    );
  }

  // ── Delete Confirmation ───────────────────────────────────────────────────

  void _confirmDelete(TradeAccount account, AzamanColors colors) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('Remove account?',
            style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'Delete your ${SupportedMethod.displayName(account.methodType)} account '
          '(${account.displayLabel})?\n\n'
          'Active ads linked to this account must be deactivated first.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('CANCEL', style: TextStyle(color: colors.textTertiary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await ref
                  .read(tradeAccountProvider.notifier)
                  .deleteAccount(account.id);
              if (mounted) {
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Account removed'
                        : 'Could not remove — may have active ads'),
                    backgroundColor:
                        success ? colors.success : colors.danger,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text('REMOVE', style: TextStyle(color: colors.danger)),
          ),
        ],
      ),
    );
  }

  // ── Add Account Bottom Sheet ──────────────────────────────────────────────

  void _showAddAccountSheet(AzamanColors colors) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _AddTradeAccountSheet(colors: colors),
    );
  }

  // ── Icon Helper ───────────────────────────────────────────────────────────

  IconData _iconForMethod(String type) {
    switch (type.toUpperCase()) {
      case 'ZELLE':
        return Icons.bolt_outlined;
      case 'CASHAPP':
        return Icons.attach_money;
      case 'VENMO':
        return Icons.credit_card_outlined;
      case 'PAYPAL':
        return Icons.payment_outlined;
      case 'APPLE_PAY':
        return Icons.apple;
      case 'GOOGLE_PAY':
        return Icons.g_mobiledata;
      case 'WISE':
        return Icons.language;
      case 'REVOLUT':
        return Icons.swap_horiz;
      case 'GIFT_CARD':
        return Icons.card_giftcard_outlined;
      case 'WESTERN_UNION':
        return Icons.send_outlined;
      case 'WIRE_TRANSFER':
        return Icons.account_balance_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }
}

// =============================================================================
// ADD TRADE ACCOUNT SHEET — Multi-step: select type → fill fields → submit
// =============================================================================

class _AddTradeAccountSheet extends ConsumerStatefulWidget {
  final AzamanColors colors;
  const _AddTradeAccountSheet({required this.colors});

  @override
  ConsumerState<_AddTradeAccountSheet> createState() =>
      _AddTradeAccountSheetState();
}

class _AddTradeAccountSheetState
    extends ConsumerState<_AddTradeAccountSheet> {
  String? _selectedType;
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  // Dynamic field controllers — allocated per type
  final Map<String, TextEditingController> _controllers = {};

  // Phase UI Sprint (2026-05-26):
  // Vendors must prove ownership of a third-party fiat handle by uploading
  // a screenshot of their profile in that app (their CashApp profile
  // screen, their Zelle profile, etc.). The previous version of this sheet
  // sent the literal string `'pending_upload'` as the screenshot URL,
  // which left admins with nothing to verify against.
  XFile? _screenshot;
  bool _isUploadingScreenshot = false;

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _selectType(String type) {
    setState(() {
      _selectedType = type;
      _controllers.clear();
      // Pre-create controllers for the selected type's fields
      for (final field in _fieldsForType(type)) {
        _controllers[field] = TextEditingController();
      }
    });
  }

  List<String> _fieldsForType(String type) {
    switch (type.toUpperCase()) {
      case 'ZELLE':
        return ['email', 'phone'];
      case 'CASHAPP':
        return ['cashtag'];
      case 'VENMO':
        return ['username', 'phone'];
      case 'PAYPAL':
        return ['email'];
      case 'APPLE_PAY':
        return ['phone'];
      case 'GOOGLE_PAY':
        return ['email', 'phone'];
      case 'WISE':
        return ['email'];
      case 'REVOLUT':
        return ['username', 'phone'];
      case 'GIFT_CARD':
        return ['cardType', 'denomination'];
      case 'WESTERN_UNION':
        return ['fullName', 'country', 'city'];
      case 'WIRE_TRANSFER':
        return ['bankName', 'accountNumber', 'routingNumber', 'swift'];
      default:
        return [];
    }
  }

  bool _isFieldRequired(String type, String field) {
    switch (type.toUpperCase()) {
      case 'ZELLE':
        return false; // email OR phone — at least one required
      case 'CASHAPP':
        return field == 'cashtag';
      case 'VENMO':
        return false; // username OR phone
      case 'PAYPAL':
        return field == 'email';
      case 'APPLE_PAY':
        return field == 'phone';
      case 'GOOGLE_PAY':
        return false; // email OR phone
      case 'WISE':
        return field == 'email';
      case 'REVOLUT':
        return false; // username OR phone
      case 'GIFT_CARD':
        return field == 'cardType';
      case 'WESTERN_UNION':
        return field == 'fullName' || field == 'country';
      case 'WIRE_TRANSFER':
        return field == 'bankName' || field == 'accountNumber';
      default:
        return false;
    }
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'email':
        return 'Email Address';
      case 'phone':
        return 'Phone (E.164, e.g. +12025551234)';
      case 'cashtag':
        return '\$Cashtag (e.g. \$YourName)';
      case 'username':
        return '@Username';
      case 'fullName':
        return 'Full Legal Name';
      case 'country':
        return 'Country';
      case 'city':
        return 'City (optional)';
      case 'cardType':
        return 'Card Type (Amazon, iTunes, Steam)';
      case 'denomination':
        return 'Denomination (optional)';
      case 'bankName':
        return 'Bank Name';
      case 'accountNumber':
        return 'Account Number';
      case 'routingNumber':
        return 'Routing Number (optional)';
      case 'swift':
        return 'SWIFT/BIC Code (optional)';
      default:
        return field;
    }
  }

  Future<void> _pickScreenshot() async {
    HapticFeedback.lightImpact();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (picked != null) {
        setState(() => _screenshot = picked);
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<String?> _uploadScreenshot() async {
    if (_screenshot == null) return null;
    setState(() => _isUploadingScreenshot = true);
    try {
      final uri = Uri.parse(
          '${AppConfig.apiUrl}/trade-accounts/upload-screenshot');
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath(
            'screenshot', _screenshot!.path));
      final res = await apiClient.multipart(
          '/trade-accounts/upload-screenshot', req);
      if (res.statusCode == 201 || res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['url'] as String?;
      }
      _showError('Screenshot upload failed (${res.statusCode}).');
      return null;
    } catch (e) {
      _showError('Screenshot upload error: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingScreenshot = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null) return;
    if (!_formKey.currentState!.validate()) return;

    if (_screenshot == null) {
      _showError('Upload a screenshot of your account profile to verify ownership.');
      return;
    }

    // Build accountDetails map (only non-empty values)
    final details = <String, dynamic>{};
    for (final entry in _controllers.entries) {
      final val = entry.value.text.trim();
      if (val.isNotEmpty) {
        details[entry.key] = val;
      }
    }

    // Validate "at least one" for OR-type fields
    final type = _selectedType!.toUpperCase();
    if ((type == 'ZELLE' || type == 'GOOGLE_PAY') &&
        details['email'] == null &&
        details['phone'] == null) {
      _showError('Please provide either email or phone');
      return;
    }
    if ((type == 'VENMO' || type == 'REVOLUT') &&
        details['username'] == null &&
        details['phone'] == null) {
      _showError('Please provide either @username or phone');
      return;
    }

    setState(() => _isSubmitting = true);

    // Upload the screenshot first; abort if upload fails so we never write
    // a TradeAccount row without a real verification artefact.
    final screenshotUrl = await _uploadScreenshot();
    if (screenshotUrl == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    final result = await ref.read(tradeAccountProvider.notifier).addAccount(
          methodType: _selectedType!,
          accountDetails: details,
          verificationScreenshot: screenshotUrl,
        );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (result != null) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Account submitted for verification!'),
            backgroundColor: widget.colors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final error = ref.read(tradeAccountProvider).error;
        _showError(error ?? 'Failed to add account');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: widget.colors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: bottomPad + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _selectedType == null
                ? 'Choose Payment Method'
                : 'Add ${SupportedMethod.displayName(_selectedType!)}',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          if (_selectedType == null) ...[
            // ── Type Selection Grid ─────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: SupportedMethod.allTypes.map((type) {
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _selectType(type);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: c.surface,
                          border: Border.all(color: c.divider),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _iconForMethodStatic(type),
                              size: 16,
                              color: c.accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              SupportedMethod.displayName(type),
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ] else ...[
            // ── Back to type selection ───────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() {
                _selectedType = null;
                _controllers.clear();
              }),
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 14, color: c.accent),
                  const SizedBox(width: 4),
                  Text(
                    'Change method',
                    style: TextStyle(color: c.accent, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Dynamic Form ────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._fieldsForType(_selectedType!).map((field) {
                        final required =
                            _isFieldRequired(_selectedType!, field);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextFormField(
                            controller: _controllers[field],
                            style: TextStyle(color: c.textPrimary),
                            keyboardType: field == 'phone' ||
                                    field == 'accountNumber' ||
                                    field == 'routingNumber'
                                ? TextInputType.phone
                                : field == 'email'
                                    ? TextInputType.emailAddress
                                    : TextInputType.text,
                            validator: required
                                ? (v) => (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null
                                : null,
                            decoration: InputDecoration(
                              labelText: _fieldLabel(field),
                              labelStyle:
                                  TextStyle(color: c.textTertiary, fontSize: 13),
                              hintText: required ? 'Required' : 'Optional',
                              hintStyle: TextStyle(
                                  color: c.textTertiary.withValues(alpha: 0.5),
                                  fontSize: 12),
                              filled: true,
                              fillColor: c.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: c.divider),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: c.divider),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: c.accent),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      // Info box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: c.accent.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: c.accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'This account will require admin verification before it can be linked to your ads.',
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // ── Profile screenshot uploader ────────────────────
                      // The vendor uploads a screenshot of their account
                      // profile screen inside the third-party app
                      // (CashApp profile, Zelle dashboard, etc.) so the
                      // admin reviewer can verify ownership.
                      Text(
                        'Profile Screenshot',
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _isUploadingScreenshot ? null : _pickScreenshot,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _screenshot != null
                                  ? c.success.withValues(alpha: 0.5)
                                  : c.divider,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: (_screenshot != null
                                          ? c.success
                                          : c.accent)
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _screenshot != null
                                    ? Image.file(
                                        File(_screenshot!.path),
                                        fit: BoxFit.cover,
                                      )
                                    : Icon(
                                        Icons.image_outlined,
                                        color: c.accent,
                                        size: 24,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _screenshot != null
                                          ? 'Screenshot ready'
                                          : 'Upload profile screenshot',
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _screenshot != null
                                          ? 'Tap to replace'
                                          : 'A screenshot of your profile inside the third-party app proves ownership.',
                                      style: TextStyle(
                                        color: c.textTertiary,
                                        fontSize: 11,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                _screenshot != null
                                    ? Icons.check_circle_outline
                                    : Icons.upload_outlined,
                                color: _screenshot != null
                                    ? c.success
                                    : c.accent,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Submit button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: Colors.black,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: (_isSubmitting || _isUploadingScreenshot)
                            ? null
                            : _submit,
                        child: (_isSubmitting || _isUploadingScreenshot)
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isUploadingScreenshot
                                        ? 'Uploading screenshot…'
                                        : 'Submitting…',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'SUBMIT FOR VERIFICATION',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconForMethodStatic(String type) {
    switch (type.toUpperCase()) {
      case 'ZELLE':
        return Icons.bolt_outlined;
      case 'CASHAPP':
        return Icons.attach_money;
      case 'VENMO':
        return Icons.credit_card_outlined;
      case 'PAYPAL':
        return Icons.payment_outlined;
      case 'APPLE_PAY':
        return Icons.apple;
      case 'GOOGLE_PAY':
        return Icons.g_mobiledata;
      case 'WISE':
        return Icons.language;
      case 'REVOLUT':
        return Icons.swap_horiz;
      case 'GIFT_CARD':
        return Icons.card_giftcard_outlined;
      case 'WESTERN_UNION':
        return Icons.send_outlined;
      case 'WIRE_TRANSFER':
        return Icons.account_balance_outlined;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }
}

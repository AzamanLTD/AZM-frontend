// =============================================================================
// AZAMAN — SEND MONEY SCREEN (Redesigned, 2026-08-27)
//
// Matches the deposit screen's visual language exactly:
//   • Same Scaffold/AppBar style (centerTitle, surface bg, same typography)
//   • Same card/surface color scheme
//   • Contacts list with AZM-IDs visible
//   • Search field to find anyone by AZM-ID or username
//   • Select a contact → amount + note → send
//
// Replaces the old chat-home routing from the "Send" home pill.
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

class SendMoneyScreen extends ConsumerStatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  ConsumerState<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends ConsumerState<SendMoneyScreen> {
  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isLoading = false;
  bool _isLookingUp = false;

  Map<String, dynamic>? _recipient;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(friendProvider).refreshAll();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _lookupRecipient() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLookingUp = true;
      _recipient = null;
      _error = null;
    });

    try {
      final api = ApiClient();
      final res = await api.get('/users/lookup?identifier=$query');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        if (data != null && data['username'] != null) {
          setState(() => _recipient = data);
        } else {
          setState(() => _error = 'User not found. Check the AZM ID.');
        }
      } else {
        setState(() => _error = 'User not found. Check the AZM ID.');
      }
    } catch (_) {
      setState(() => _error = 'Could not look up recipient. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  void _selectContact(Map<String, dynamic> friend) {
    AzamanHaptics.nav();
    final friendObj = friend['friend'] is Map<String, dynamic>
        ? friend['friend'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final username = (friendObj['username'] ??
            friend['username'] ??
            friend['friendUsername'] ??
            'Unknown')
        .toString();

    final friendIdRaw = friendObj['id'] ?? friend['friendId'] ?? friend['userId'] ?? 0;
    final friendId = friendIdRaw is int
        ? friendIdRaw
        : int.tryParse(friendIdRaw.toString()) ?? 0;

    setState(() {
      _recipient = {
        'username': username,
        'fullName': friendObj['fullName']?.toString(),
        'azamanId': friendObj['azamanId']?.toString() ?? 'AZM-\u2022\u2022\u2022',
        'id': friendId,
        'profilePictureUrl': friendObj['profilePictureUrl']?.toString(),
      };
      _error = null;
      _successMessage = null;
      _searchController.clear();
    });
  }

  Future<void> _send() async {
    if (_recipient == null) return;
    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }

    final identifier = _recipient!['azamanId']?.toString().isNotEmpty == true
        ? _recipient!['azamanId']
        : _recipient!['username'];

    setState(() { _isLoading = true; _error = null; });
    AzamanHaptics.confirm();
    try {
      final api = ApiClient();
      final res = await api.post('/finance/internal-transfer', {
        'recipientIdentifier': identifier,
        'amountUsdc': amount,
        if (_noteController.text.trim().isNotEmpty)
          'note': _noteController.text.trim(),
      });
      if (res.statusCode == 200 || res.statusCode == 201) {
        AzamanHaptics.commit();
        setState(() {
          _successMessage = 'Sent $amountStr USDC successfully.';
          _recipient = null;
        });
        _amountController.clear();
        _noteController.clear();
      } else {
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        final msg = data?.containsKey('message') == true
            ? data!['message'].toString()
            : 'Transfer failed. Please try again.';
        setState(() => _error = msg);
      }
    } catch (_) {
      setState(() => _error = 'Transfer failed. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final balance = ref.watch(authProvider).user?.availableBalance ?? 0.0;
    final myAzamanId = ref.watch(authProvider).user?.azamanId ?? '';

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: colors.textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Send',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Balance chip ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.accentSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.wallet_outlined, size: 16, color: colors.accent),
                  const SizedBox(width: 8),
                  Text('Available: ${balance.toStringAsFixed(2)} USDC',
                      style: TextStyle(
                          color: colors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (myAzamanId.isNotEmpty)
                    Text('Your ID: $myAzamanId',
                        style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Search / AZM-ID input ─────────────────────────────────────
              Text('Send to',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search AZM ID or username',
                      hintStyle: TextStyle(color: colors.textTertiary),
                      prefixIcon: Icon(Icons.person_search_outlined,
                          color: colors.textTertiary, size: 18),
                      filled: true,
                      fillColor: colors.card,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: colors.accent.withValues(alpha: 0.5))),
                    ),
                    onSubmitted: (_) => _lookupRecipient(),
                  ),
                ),
                const SizedBox(width: 10),
                ScaleTap(
                  onTap: _lookupRecipient,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(12)),
                    child: _isLookingUp
                        ? Padding(
                            padding: const EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.isDark
                                    ? Colors.black
                                    : Colors.white))
                        : Icon(Icons.search_rounded,
                            color: colors.isDark ? Colors.black : Colors.white,
                            size: 20),
                  ),
                ),
              ]),

              // ── Recipient card ────────────────────────────────────────────
              if (_recipient != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: colors.accent.withValues(alpha: 0.3))),
                  child: Row(children: [
                    _RecipientAvatar(recipient: _recipient!, colors: colors),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_recipient!['username'] ?? '',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            if (_recipient!['fullName'] != null)
                              Text(_recipient!['fullName'],
                                  style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 12)),
                            if (_recipient!['azamanId'] != null)
                              Text(_recipient!['azamanId'],
                                  style: TextStyle(
                                      color: colors.accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                          ]),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: colors.textTertiary),
                      onPressed: () => setState(() {
                        _recipient = null;
                        _error = null;
                      }),
                    ),
                  ]),
                ),
              ],

              // ── Contacts list ─────────────────────────────────────────────
              if (_recipient == null) ...[
                const SizedBox(height: 20),
                Text('Your contacts',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _ContactsList(
                  onSelect: _selectContact,
                  colors: colors,
                ),
              ],

              // ── Amount + Note ─────────────────────────────────────────────
              if (_recipient != null) ...[
                const SizedBox(height: 24),
                Text('Amount (USDC)',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                    prefixText: 'USDC  ',
                    prefixStyle: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    filled: true,
                    fillColor: colors.card,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: colors.accent.withValues(alpha: 0.5))),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _noteController,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Add a note (optional)',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    prefixIcon: Icon(Icons.note_outlined,
                        color: colors.textTertiary, size: 18),
                    filled: true,
                    fillColor: colors.card,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ],

              // ── Error / success ───────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: colors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded,
                        color: colors.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: colors.danger, fontSize: 13))),
                  ]),
                ),
              ],
              if (_successMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: colors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: colors.success, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_successMessage!,
                            style: TextStyle(
                                color: colors.success, fontSize: 13))),
                  ]),
                ),
              ],

              // ── Send button ──────────────────────────────────────────────
              if (_recipient != null) ...[
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor:
                          colors.isDark ? Colors.black : Colors.white,
                      disabledBackgroundColor: colors.divider,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: colors.isDark
                                    ? Colors.black
                                    : Colors.white))
                        : const Text('Send',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contacts list — reads from friendProvider, shows AZM-IDs on each row.
// ─────────────────────────────────────────────────────────────────────────────
class _ContactsList extends ConsumerWidget {
  final void Function(Map<String, dynamic>) onSelect;
  final AzamanColors colors;

  const _ContactsList({required this.onSelect, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendProvider).friends;

    if (friends.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline_rounded, size: 48,
                  color: colors.textTertiary.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text('No contacts yet',
                  style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Search for someone by their AZM ID to send money.',
                  style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final friend = friends[i];
        final friendObj = friend['friend'] is Map<String, dynamic>
            ? friend['friend'] as Map<String, dynamic>
            : const <String, dynamic>{};

        final username = (friendObj['username'] ??
                friend['username'] ??
                friend['friendUsername'] ??
                'Unknown')
            .toString();

        final azamanId = friendObj['azamanId']?.toString();
        final profilePic = friendObj['profilePictureUrl']?.toString();

        return ScaleTap(
          onTap: () => onSelect(friend),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider, width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.accentSurface,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: profilePic != null && profilePic.isNotEmpty
                        ? AzamanNetworkImage(
                            imageUrl: profilePic,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _initials(username, colors),
                          )
                        : _initials(username, colors),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(username,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      if (azamanId != null && azamanId.isNotEmpty)
                        Text(azamanId,
                            style: TextStyle(
                                color: colors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(Icons.send_rounded, size: 16, color: colors.textTertiary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _initials(String name, AzamanColors colors) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Center(
      child: Text(initial,
          style: TextStyle(
              color: colors.accent,
              fontWeight: FontWeight.w800,
              fontSize: 16)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recipient avatar — small circular avatar with image or initials fallback.
// ─────────────────────────────────────────────────────────────────────────────
class _RecipientAvatar extends StatelessWidget {
  final Map<String, dynamic> recipient;
  final AzamanColors colors;

  const _RecipientAvatar({required this.recipient, required this.colors});

  @override
  Widget build(BuildContext context) {
    final pic = recipient['profilePictureUrl']?.toString();
    final username = (recipient['username'] ?? '?').toString();
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.accentSurface,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: pic != null && pic.isNotEmpty
            ? AzamanNetworkImage(
                imageUrl: pic,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Center(
                  child: Text(initial,
                      style: TextStyle(
                          color: colors.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                ),
              )
            : Center(
                child: Text(initial,
                    style: TextStyle(
                        color: colors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ),
      ),
    );
  }
}

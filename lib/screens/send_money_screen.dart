// =============================================================================
// AZAMAN — SEND MONEY SCREEN (Redesigned 2026-08-27; r43 canonical-rail 2026-10-17)
//
// Matches the deposit screen's visual language exactly:
//   • Same Scaffold/AppBar style (centerTitle, surface bg, same typography)
//   • Same card/surface color scheme
//   • Contacts list (accepted friends — the only users the transfer rail serves)
//   • Search by AZM-ID or username through the REAL identity rails
//   • Select a recipient → amount + note → send
//
// r43 TRUTHFUL WIRING (Workstream C, P0): this screen used to post to
// POST /finance/internal-transfer and GET /users/lookup?identifier= — routes
// that have NEVER existed on the backend. Every send failed; every lookup
// failed. Worse, contact rows fabricated 'AZM-•••' identifiers and shipped
// them to the server. The ONLY user-to-user transfer rail is friendship-
// scoped: POST /api/friends/transfer/send { friendshipId, amount } (2FA +
// durable financial idempotency). This screen now:
//   • Sends exclusively through FriendService.sendFunds — a friendshipId
//     resolved from a real rail, never invented.
//   • Resolves AZM-IDs via GET /users/lookup/:azamanId (r43 backend
//     enrichment returns the caller's friendship state with the found user).
//   • Resolves usernames via GET /friends/search?q= (friendshipStatus per hit).
//   • FAILS CLOSED: a recipient without an ACCEPTED friendship shows the
//     truthful reason (pending request / not friends yet) and CANNOT send.
//     No fabricated identifiers anywhere — an AZM ID line renders only when
//     a real rail returned one.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/widgets/home/activity_actions.dart'
    show ActivityRecipient;
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/services/friend_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/services/az_sound.dart';
import 'package:azaman/widgets/scale_tap.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

class SendMoneyScreen extends ConsumerStatefulWidget {
  /// AUTHORITATIVE recipient seed (NEW-HOME §13 "Send Again"): when the
  /// caller carries an explicit recipient payload from a real transaction
  /// record, the screen opens with that recipient already resolved — no
  /// re-derivation, no guessing. Null = the normal search flow.
  const SendMoneyScreen({super.key, this.initialRecipient});

  final ActivityRecipient? initialRecipient;

  @override
  ConsumerState<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends ConsumerState<SendMoneyScreen> {
  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isLoading = false;
  bool _isLookingUp = false;

  /// The resolved recipient. Invariant (r43): `friendshipId` is present
  /// IFF this recipient is sendable — it is always a real id from a real
  /// rail (the friends list, the AZM-ID lookup's friendship state, or the
  /// paginated friendship resolver). Never fabricated, never guessed.
  /// `azamanId` is only present when a real rail returned one.
  Map<String, dynamic>? _recipient;

  /// Username-search hits awaiting the user's pick (real rows from
  /// GET /friends/search — never synthesized).
  List<Map<String, dynamic>> _searchResults = const [];

  final FriendService _friends = FriendService();
  String? _error;
  String? _successMessage;

  /// r43 wire contract: exactly AZM- + 9 digits (mirrors AZAMAN_ID_RE).
  static final RegExp _azamanIdRe = RegExp(r'^AZM-\d{9}$');

  bool get _canSend => _recipient?['friendshipId'] is String;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(friendProvider).refreshAll();
      // r43: the "Send Again" seed is a HINT, not a proof. The AZM ID a past
      // transaction record carried is resolved against the live identity
      // rail — which also answers the only question that matters here:
      // the caller's friendship state with that user (the transfer rail is
      // friendship-scoped). The old screen just asserted the seed resolved;
      // that was never true.
      final seed = widget.initialRecipient;
      if (seed != null) {
        _resolveSeed(seed.azamanId);
      }
    });
  }

  /// Seed resolution never fabricates: the AZM ID either resolves through
  /// the identity rail (with the caller's friendship state) or the screen
  /// shows the truthful reason it could not.
  Future<void> _resolveSeed(String azamanId) async {
    setState(() => _isLookingUp = true);
    try {
      await _resolveAzamanId(azamanId);
    } on LookupFailure catch (e) {
      if (mounted) {
        setState(() => _error = switch (e.errorCode) {
          'USER_NOT_FOUND' => 'That account is no longer available.',
          'AZAMAN_ID_SELF' => "That's your own AZM ID.",
          _ => e.message,
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not resolve that recipient. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  /// Truthful capability line for the recipient card: WHY this recipient
  /// can or cannot receive right now. Null = sendable, no line needed.
  String? _statusLine() {
    final status = _recipient?['friendshipStatus']?.toString();
    if (_canSend) return null;
    return switch (status) {
      'PENDING' => 'Friend request pending — you can send once they accept.',
      'ACCEPTED' => 'Resolving your friendship… pick them from your contacts '
          'list if this persists.',
      _ => 'Only friends can receive transfers. Add them as a friend first.',
    };
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
      _searchResults = const [];
      _error = null;
    });

    try {
      // r43 — AZM-ID-shaped queries go to the canonical identity rail;
      // anything else is a username search. Both are REAL routes; the old
      // /users/lookup?identifier= call never matched anything on the
      // backend.
      if (_azamanIdRe.hasMatch(query.toUpperCase())) {
        await _resolveAzamanId(query);
      } else {
        final hits =
            await _friends.searchUsers(query, _tokenOrThrow);
        if (!mounted) return;
        if (hits.isEmpty) {
          setState(() => _error =
              'No user found with that username.');
          return;
        }
        if (hits.length == 1) {
          await _selectSearchHit(hits.first);
        } else {
          // Real rows from the friends-search rail — the user picks one.
          setState(() => _searchResults = hits);
        }
      }
    } on LookupFailure catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.errorCode) {
          case 'USER_NOT_FOUND':
            _error = 'No user with that AZM ID.';
          case 'AZAMAN_ID_SELF':
            _error = "That's your own AZM ID.";
          case 'AZAMAN_ID_INVALID':
            _error = 'AZM IDs look like AZM- followed by 9 digits.';
          default:
            _error = e.message;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not look up recipient. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  /// Resolve an AZM ID through GET /users/lookup/:azamanId (r43). The
  /// response carries the CALLER's friendship state with the found user;
  /// only ACCEPTED yields a sendable recipient.
  Future<void> _resolveAzamanId(String azamanId) async {
    final user = await _friends.lookupByAzamanId(azamanId);
    if (!mounted) return;

    final friendship = user['friendship'];
    final status = friendship is Map<String, dynamic>
        ? friendship['status']?.toString()
        : null;
    final friendshipId = friendship is Map<String, dynamic>
        ? friendship['friendshipId']?.toString()
        : null;

    setState(() {
      _searchController.clear();
      _searchResults = const [];
      _recipient = <String, dynamic>{
        'username': user['displayName']?.toString() ?? 'AZAMAN user',
        'azamanId': user['azamanId']?.toString(),
        'profilePictureUrl': user['avatar']?.toString(),
        if (status == 'ACCEPTED' &&
            friendshipId != null &&
            friendshipId.isNotEmpty)
          'friendshipId': friendshipId,
        'friendshipStatus': status,
      };
      _error = null;
      _successMessage = null;
    });
  }

  /// A real username-search hit (GET /friends/search). The row carries the
  /// caller's friendshipStatus with that user; ACCEPTED needs the
  /// friendshipId resolved from a real rail before the send unlocks.
  Future<void> _selectSearchHit(Map<String, dynamic> hit) async {
    setState(() {
      _isLookingUp = true;
      _error = null;
    });

    final username = hit['username']?.toString() ?? 'AZAMAN user';
    final status = hit['friendshipStatus']?.toString();
    final rawId = hit['id'];
    final userId = rawId is int ? rawId : int.tryParse('$rawId');

    if (status == 'ACCEPTED' && userId != null) {
      final friendshipId = await _resolveFriendshipId(userId);
      if (!mounted) return;
      if (friendshipId == null) {
        // FAIL CLOSED — the rail could not prove the friendship, so no
        // send. Truthful, specific, and non-blocking: the user can pick
        // the same person from the contacts list.
        setState(() {
          _isLookingUp = false;
          _searchController.clear();
          _searchResults = const [];
          _recipient = <String, dynamic>{
            'username': username,
            'profilePictureUrl': hit['profilePictureUrl']?.toString(),
            'friendshipStatus': status,
          };
          _error = "Couldn't resolve your friendship with $username — "
              'pick them from your contacts list below to send.';
        });
        return;
      }
      setState(() {
        _isLookingUp = false;
        _searchController.clear();
        _searchResults = const [];
        _recipient = <String, dynamic>{
          'username': username,
          'profilePictureUrl': hit['profilePictureUrl']?.toString(),
          'friendshipId': friendshipId,
          'friendshipStatus': status,
        };
        _successMessage = null;
      });
      return;
    }

    // PENDING or stranger: truthful, non-sendable recipient card.
    setState(() {
      _isLookingUp = false;
      _searchController.clear();
      _searchResults = const [];
      _recipient = <String, dynamic>{
        'username': username,
        'profilePictureUrl': hit['profilePictureUrl']?.toString(),
        'friendshipStatus': status,
      };
    });
  }

  /// friendshipId for an ACCEPTED friend, from a REAL rail only:
  /// the provider's cached rows first, then the paginated /friends
  /// resolver. Null means unprovable — callers fail closed.
  Future<String?> _resolveFriendshipId(int userId) async {
    final cached = ref.read(friendProvider).friends;
    for (final row in cached) {
      final friend = row['friend'];
      final id = friend is Map<String, dynamic> ? friend['id'] : null;
      final parsed = id is int ? id : int.tryParse('$id');
      if (parsed == userId) {
        final fid = row['friendshipId']?.toString();
        if (fid != null && fid.isNotEmpty) return fid;
      }
    }
    final row = await _friends.findFriendshipByUserId(userId, _tokenOrThrow);
    return row?['friendshipId']?.toString();
  }

  String get _tokenOrThrow {
    final token = ref.read(authProvider).user?.token;
    if (token == null) {
      throw const LookupFailure(
        statusCode: 401,
        errorCode: 'NO_SESSION',
        message: 'Session expired — sign in again.',
      );
    }
    return token;
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

    // r43 — the transfer rail is friendship-scoped: the friendshipId IS
    // the send capability. The old code fabricated 'AZM-•••' here and
    // posted it as a recipient identifier to a route that never existed.
    // The friends payload carries no azamanId, so none is displayed —
    // invented identifiers are gone.
    final friendshipId = friend['friendshipId']?.toString();
    if (friendshipId == null || friendshipId.isEmpty) {
      setState(() {
        _error = 'This contact could not be resolved to a friendship — '
            'pull-to-refresh your contacts and try again.';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _recipient = {
        'username': username,
        'friendshipId': friendshipId,
        'friendshipStatus': 'ACCEPTED',
        'profilePictureUrl': friendObj['profilePictureUrl']?.toString(),
      };
      _error = null;
      _successMessage = null;
      _searchController.clear();
      _searchResults = const [];
    });
  }

  Future<void> _send() async {
    // r43 — fail closed BEFORE any haptics or rail call: no resolved
    // ACCEPTED friendshipId, no send. The truthful status is already on
    // the recipient card.
    if (_recipient == null || !_canSend) return;
    final friendshipId = _recipient!['friendshipId'] as String;
    final amountStr = _amountController.text.trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    final balance = ref.read(authProvider).user?.availableBalance ?? 0.0;
    if (amount > balance) {
      setState(() =>
          _error = 'Amount exceeds your available balance of '
              '\${balance.toStringAsFixed(2)} USDC.');
      return;
    }

    final note = _noteController.text.trim();

    setState(() { _isLoading = true; _error = null; });
    AzamanHaptics.confirm();
    try {
      // THE canonical user-to-user transfer rail — same call the friends
      // hub transfer sheet makes: POST /api/friends/transfer/send with 2FA
      // and durable financial idempotency (postFinancial inside
      // sendFunds). One logical transfer, one durable identity.
      await _friends.sendFunds(
        friendshipId,
        amount,
        note.isNotEmpty ? note : null,
        _tokenOrThrow,
      );
      AzamanHaptics.commit();
      AzSound.success();
      if (!mounted) return;
      setState(() {
        _successMessage = 'Sent \$$amountStr USDC successfully.';
        _recipient = null;
      });
      _amountController.clear();
      _noteController.clear();
    } on LookupFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      // sendFunds throws Exception('Failed to send funds: <body>') with the
      // backend message inline — surface it truthfully when present.
      final raw = e.toString();
      final msg = raw.startsWith('Exception: Failed to send funds:')
          ? raw.substring('Exception: Failed to send funds:'.length).trim()
          : null;
      setState(() => _error =
          (msg != null && msg.isNotEmpty) ? msg : 'Transfer failed. Please try again.');
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
                  // r43: Flexible+ellipsis — long IDs and balances can
                  // exceed narrow viewports; the old fixed Row overflowed.
                  if (myAzamanId.isNotEmpty)
                    Flexible(
                      child: Text('Your ID: $myAzamanId',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
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

              // ── Search results (r43 — real /friends/search rows) ────────
              if (_searchResults.isNotEmpty && _recipient == null) ...[
                const SizedBox(height: 12),
                Text('Search results',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._searchResults.map((hit) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SearchResultRow(
                        hit: hit,
                        colors: colors,
                        onTap: () => _selectSearchHit(hit),
                      ),
                    )),
              ],

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
                            // r43 — the truthful capability line: why this
                            // recipient can/cannot receive right now.
                            if (_statusLine() != null) ...[
                              const SizedBox(height: 4),
                              Text(_statusLine()!,
                                  style: TextStyle(
                                      color: colors.textTertiary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ],
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
              // r43: amount entry only appears for a SENDABLE recipient —
              // no amount UI for a pending request or a stranger.
              if (_recipient != null && _canSend) ...[
                const SizedBox(height: 24),
                Text('Amount (USDC)',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('send-amount-field'),
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
              if (_recipient != null && _canSend) ...[
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
              // r43 — truthful: searching finds people, but only accepted
              // friends can RECEIVE a transfer (the rail is friendship-
              // scoped). The old copy implied AZM-ID search = sendable.
              Text('Add friends to send them money — search finds people by '
                  'AZM ID or username, but only accepted friends can receive.',
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

        // r43 — the friends payload carries NO azamanId; the old row
        // rendered one from this field only when present (never), and the
        // selection handler fabricated 'AZM-•••'. Username + avatar is the
        // truthful row; the AZM ID line is gone by design.
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
// Search result row (r43) — a REAL /friends/search hit with the caller's
// friendshipStatus projected truthfully. No fabricated identifiers.
// ─────────────────────────────────────────────────────────────────────────────
class _SearchResultRow extends StatelessWidget {
  final Map<String, dynamic> hit;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _SearchResultRow({
    required this.hit,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final username = hit['username']?.toString() ?? 'AZAMAN user';
    final pic = hit['profilePictureUrl']?.toString();
    final status = hit['friendshipStatus']?.toString();
    final isAccepted = status == 'ACCEPTED';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return ScaleTap(
      onTap: onTap,
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
                                  fontSize: 14)),
                        ),
                      )
                    : Center(
                        child: Text(initial,
                            style: TextStyle(
                                color: colors.accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(username,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
            // Truthful capability tag — the only three real states.
            Text(
              switch (status) {
                'ACCEPTED' => 'Friend',
                'PENDING' => 'Request pending',
                _ => 'Not connected',
              },
              style: TextStyle(
                  color: isAccepted
                      ? colors.success
                      : colors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
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

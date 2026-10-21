// =============================================================================
// AZAMAN — RECIPIENT SELECTOR SHEET (unified Send, 2026-10-20)
//
// The focused recipient-selection surface for the shared Send composer.
// One sheet, three honest resolution modes over LIVE backend contracts:
//
//   1. Accepted friends — the authoritative relationship source
//      (friendProvider rows: friendshipId + username + avatar). Any
//      selected friend is send-capable.
//   2. Directory search — /friends/search?q= (username or numeric user
//      id). Hits are cross-matched against the friend rows; results are
//      explicit selections with a Friend / Not connected chip. Not
//      connected ≠ send-capable: the rail is friendship-based and the
//      sheet never silently creates a friendship.
//   3. AZM-ID lookup — /users/lookup/:azamanId (AZM- followed by 9
//      digits, never interpolated raw). The identity contract projects
//      no User.id, so a hit is honestly Not connected.
//
// QR: the scanner runs in pickUsername mode over the SAME audited
// person-identity payload (azaman://user/{username} / @username).
// Reservation check-in codes and dine-in table codes are rejected —
// they are not a payment identity. A scanned username runs the normal
// directory search and requires EXPLICIT selection.
//
// Async honesty: a generation counter drops stale responses (only the
// newest search renders). Self-lookup is blocked instantly client-side
// and typed errors never fake a result.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/qr_scanner_screen.dart';
import 'package:azaman/services/recipient_discovery_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/scale_tap.dart';

/// Opens the recipient selector. Returns the explicitly selected
/// recipient (never a placeholder) or null when dismissed.
Future<SendRecipient?> showRecipientSelectorSheet(
  BuildContext context, {
  SendRecipient? currentRecipient,
  RecipientDiscoveryService? discovery,
}) {
  return showModalBottomSheet<SendRecipient>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _RecipientSelectorSheet(
        currentRecipient: currentRecipient, discovery: discovery),
  );
}

class _RecipientSelectorSheet extends ConsumerStatefulWidget {
  const _RecipientSelectorSheet({this.currentRecipient, this.discovery});

  final SendRecipient? currentRecipient;
  final RecipientDiscoveryService? discovery;

  @override
  ConsumerState<_RecipientSelectorSheet> createState() =>
      _RecipientSelectorSheetState();
}

class _RecipientSelectorSheetState
    extends ConsumerState<_RecipientSelectorSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  int _generation = 0;
  bool _searching = false;
  bool _networkFailed = false;
  String? _lookupError;

  List<SendRecipient> _friends = const [];
  List<SendRecipient> _directory = const [];
  SendRecipient? _azmHit;

  late final RecipientDiscoveryService _discovery =
      widget.discovery ?? RecipientDiscoveryService();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
    _seedFriends();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(friendProvider).refreshAll();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The friend list is the authoritative friendship source. It is
  /// re-read from the provider on every rebuild so a fresh fetch shows
  /// immediately.
  void _seedFriends() {
    final rows = ref.read(friendProvider).friends;
    final resolved = RecipientDiscoveryService.fromFriendRows(rows);
    if (mounted) setState(() => _friends = resolved);
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() {
        _directory = const [];
        _azmHit = null;
        _lookupError = null;
        _networkFailed = false;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _resolve(q));
  }

  bool _isAzmIdPattern(String q) => RegExp(r'^AZM-\d{9}$').hasMatch(q);

  Future<void> _resolve(String q) async {
    final gen = ++_generation;
    final myAzamanId = ref.read(authProvider).user?.azamanId;
    setState(() {
      _searching = true;
      _lookupError = null;
      _networkFailed = false;
    });

    if (_isAzmIdPattern(q)) {
      final outcome =
          await _discovery.lookupByAzamanId(q, myAzamanId: myAzamanId);
      if (gen != _generation) return; // stale response — never render it
      if (!mounted) return;
      setState(() {
        _searching = false;
        _azmHit = null;
        _directory = const [];
        switch (outcome.status) {
          case AzmLookupStatus.found:
            _azmHit = outcome.recipient;
            break;
          case AzmLookupStatus.self:
            _lookupError = "That's your own AZM ID.";
            break;
          case AzmLookupStatus.notFound:
            _lookupError = 'No active account with that AZM ID.';
            break;
          case AzmLookupStatus.malformed:
            _lookupError = 'An AZM ID looks like AZM-123456789.';
            break;
          case AzmLookupStatus.network:
            _networkFailed = true;
            break;
        }
      });
      return;
    }

    // Directory search (username / numeric id) — user text is ALWAYS
    // component-encoded by the service, never interpolated raw.
    final friendRows = ref.read(friendProvider).friends;
    final outcome = await _discovery.searchDirectory(q, friendRows: friendRows);
    if (gen != _generation) return;
    if (!mounted) return;
    setState(() {
      _searching = false;
      _azmHit = null;
      _directory = outcome.results;
      _networkFailed = outcome.networkFailed;
    });
  }

  Future<void> _scanQr() async {
    AzamanHaptics.nav();
    _searchFocus.unfocus();
    final username = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen.pickUsername()),
    );
    if (username == null || !mounted) return;
    _searchController.text = username;
    _resolve(username);
  }

  void _select(SendRecipient r) {
    AzamanHaptics.toggle();
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final query = _searchController.text.trim();
    final friends = query.isEmpty || _isAzmIdPattern(query)
        ? _friends
        : _friends
            .where((f) =>
                (f.username ?? '')
                    .toLowerCase()
                    .contains(query.toLowerCase()) ||
                (f.displayName
                        ?.toLowerCase()
                        .contains(query.toLowerCase()) ??
                    false))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Choose recipient',
                          key: const ValueKey('send-selector-title'),
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                    ScaleTap(
                      key: const ValueKey('send-selector-qr'),
                      onTap: _scanQr,
                      child: Semantics(
                        button: true,
                        label: 'Scan a personal AZAM QR code',
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.qr_code_scanner,
                              size: 20, color: colors.accent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: TextField(
                  key: const ValueKey('send-selector-search'),
                  controller: _searchController,
                  focusNode: _searchFocus,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Name, username or AZM ID',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    prefixIcon: Icon(Icons.search,
                        color: colors.textTertiary, size: 20),
                    filled: true,
                    fillColor: colors.card,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12 + bottomInset),
                  children: [
                    if (friends.isNotEmpty) ...[
                      _SectionHeader(colors: colors, label: 'Your friends'),
                      for (final f in friends)
                        _RecipientRow(
                          colors: colors,
                          recipient: f,
                          onTap: () => _select(f),
                        ),
                    ],
                    if (_azmHit != null) ...[
                      _SectionHeader(colors: colors, label: 'AZM ID match'),
                      _RecipientRow(
                        colors: colors,
                        recipient: _azmHit!,
                        onTap: () => _select(_azmHit!),
                      ),
                    ],
                    if (_directory.isNotEmpty) ...[
                      _SectionHeader(
                          colors: colors,
                          label:
                              'Directory${_directory.length > 1 ? ' (${_directory.length})' : ''}'),
                      for (final d in _directory)
                        _RecipientRow(
                          colors: colors,
                          recipient: d,
                          onTap: () => _select(d),
                        ),
                    ],
                    if (_searching)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))),
                      ),
                    if (_lookupError != null && !_searching)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(_lookupError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 13)),
                          ),
                        ),
                    if (_networkFailed && !_searching)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Could not reach the directory. Check your connection and try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 13),
                            ),
                          ),
                        ),
                    if (!_searching &&
                        _lookupError == null &&
                        !_networkFailed &&
                        friends.isEmpty &&
                        _directory.isEmpty &&
                        _azmHit == null &&
                        query.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'No matches. You can send to accepted friends.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 13),
                            ),
                          ),
                        ),
                    if (friends.isEmpty && query.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'No friends yet. Search a username or AZM ID — you can send once you are connected.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 13),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.colors, required this.label});
  final AzamanColors colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6)),
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.colors,
    required this.recipient,
    required this.onTap,
  });

  final AzamanColors colors;
  final SendRecipient recipient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = recipient;
    final url = r.avatarUrl;
    return Semantics(
      button: true,
      label: 'Select ${r.name}${r.canReceive ? '' : ', not connected'}',
      child: ScaleTap(
        onTap: onTap,
        child: Container(
          key: ValueKey('send-selector-row-${r.username}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: r.canReceive ? colors.divider : colors.danger),
          ),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: url != null
                      ? AzamanNetworkImage(imageUrl: url, fit: BoxFit.cover)
                      : Center(
                          child: Text(
                            r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
                            style: TextStyle(
                                color: colors.accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      // Honest identity: AZM ID alone when the
                      // backend returned no username — the display
                      // name is never fabricated into a handle
                      // (PR #165 review finding 4).
                      r.identityLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: r.canReceive
                      ? colors.accentSurface
                      : colors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  r.canReceive ? 'Friend' : 'Not connected',
                  style: TextStyle(
                      color: r.canReceive ? colors.accent : colors.danger,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

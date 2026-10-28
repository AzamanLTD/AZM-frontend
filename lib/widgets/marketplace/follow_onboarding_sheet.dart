// lib/widgets/marketplace/follow_onboarding_sheet.dart
// =============================================================================
// I1 — Marketplace Follow Onboarding: the selection experience.
//
// Opened from the spotlight card on Marketplace home. Honesty rules
// (spec §3-§6):
//
//  * ONLY real, eligible businesses from the existing catalogue search
//    (GET /business/search) — nothing invented, no popularity claims;
//  * selecting a row is NOT a follow: nothing mutates until the user
//    confirms the whole selection;
//  * each confirmed follow is an individual POST /follows (canonical
//    BusinessProfile.id) with its own honest result — partial success
//    is reported as exactly what it is, failed rows can be retried
//    without touching the succeeded ones, and a pending request can
//    never be duplicated;
//  * completion needs min(5, eligible count) CONFIRMED follows when
//    five or more businesses are eligible; with fewer than five the
//    user is never trapped by the catalogue size: their own honest
//    selection completes, and a persistently failing row still has
//    the discovery fallback (browse the marketplace) as an exit;
//  * "Maybe later" leaves with zero mutations (nothing selected and
//    nothing requested — this sheet's close is not the spotlight's
//    dismissal and does not persist anything);
//  * rows show identity, logo/category, verification and an
//    accessible selection control; the confirmed count is always
//    exact.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/providers/theme_provider.dart'
    show themeProvider, AzamanColors;
import 'package:azaman/widgets/azaman_network_image.dart';

/// The per-business follow request lifecycle inside the sheet. Only
/// the CONFIRMED result of a real request may become [confirmed].
enum _FollowPickStatus { idle, pending, confirmed, failed }

class _FollowPickRow {
  _FollowPickRow(this.business)
    : status = _FollowPickStatus.idle,
      selected = false,
      attempts = 0;

  final BusinessProfile business;

  _FollowPickStatus status;
  bool selected;

  /// Real POST /follows attempts for this row — pinned by tests: a
  /// succeeded row can never be re-requested, and a pending one can
  /// never race a second tap.
  int attempts;
}

class FollowOnboardingSheet extends ConsumerStatefulWidget {
  const FollowOnboardingSheet.show({
    super.key,
    ApiClient? api,
    BusinessService? service,
  }) : _api = api,
       _service = service;

  final ApiClient? _api;
  final BusinessService? _service;

  static Future<void> open(
    BuildContext context, {
    ApiClient? api,
    BusinessService? service,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) =>
          FollowOnboardingSheet.show(api: api, service: service),
    );
  }

  @override
  ConsumerState<FollowOnboardingSheet> createState() =>
      _FollowOnboardingSheetState();
}

class _FollowOnboardingSheetState extends ConsumerState<FollowOnboardingSheet> {
  final List<_FollowPickRow> _rows = [];
  bool _loading = true;
  bool _submitting = false;
  bool _done = false;
  String? _loadError;

  ApiClient? _api;
  BusinessService? _service;

  static const _targetFollows = 5;

  @override
  void initState() {
    super.initState();
    _api = widget._api ?? apiClient;
    _service = widget._service ?? BusinessService();
    _loadEligible();
  }

  /// Real catalogue businesses only. Eligible = listed by the real
  /// search, not suspended, and (when the caller's own business is
  /// known) not the user's own — the backend rejects self-follows and
  /// the sheet must not offer a row that can only fail.
  Future<void> _loadEligible() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await _service!.searchBusinesses(limit: 20);
      final mine = await _ownBusiness();
      if (!mounted) return;
      final eligible = page.businesses.where(
        (b) => !b.isSuspended && b.id != mine?.id,
      );
      setState(() {
        _rows
          ..clear()
          ..addAll(eligible.map(_FollowPickRow.new));
        _loading = false;
      });
    } catch (_) {
      // Honest failure: no invented fallback list.
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              'Could not load businesses right now. Try again in a moment.';
        });
      }
    }
  }

  Future<BusinessProfile?> _ownBusiness() async {
    try {
      return await _service!.getMyBusiness();
    } catch (_) {
      // Anonymous caller or no business profile — honest absence.
      return null;
    }
  }

  int get _selectedCount => _rows
      .where((r) => r.selected && r.status == _FollowPickStatus.idle)
      .length;

  int get _confirmedCount =>
      _rows.where((r) => r.status == _FollowPickStatus.confirmed).length;

  int get _failedCount =>
      _rows.where((r) => r.status == _FollowPickStatus.failed).length;

  bool get _anyPending =>
      _rows.any((r) => r.status == _FollowPickStatus.pending);

  void _toggleSelect(_FollowPickRow row) {
    if (_submitting || row.status != _FollowPickStatus.idle) return;
    setState(() => row.selected = !row.selected);
  }

  /// Confirm the selection: one REAL POST /follows per selected row,
  /// each tracked individually. Duplicate-proof: rows flip to pending
  /// synchronously, the button is dead while anything is in flight,
  /// and retry re-fires only failed rows.
  Future<void> _confirmSelection() async {
    // A fresh attempt takes: freshly selected idle rows, PLUS every
    // row whose previous real request FAILED (retry). Confirmed and
    // pending rows are never re-requested — a retry can never undo or
    // duplicate a successful follow.
    final pending = _rows
        .where(
          (r) =>
              (r.selected && r.status == _FollowPickStatus.idle) ||
              r.status == _FollowPickStatus.failed,
        )
        .toList(growable: false);
    if (pending.isEmpty || _anyPending) return;
    setState(() {
      _submitting = true;
      for (final r in pending) {
        r.status = _FollowPickStatus.pending;
        r.attempts++;
      }
    });

    await Future.wait(
      pending.map((r) async {
        try {
          final res = await _api!.post('/follows', {
            'businessProfileId': r.business.id,
          });
          final ok = res.statusCode >= 200 && res.statusCode < 300;
          if (!mounted) return;
          setState(() {
            r.status = ok
                ? _FollowPickStatus.confirmed
                : _FollowPickStatus.failed;
          });
        } catch (_) {
          if (!mounted) return;
          setState(() => r.status = _FollowPickStatus.failed);
        }
      }),
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    // Completion is judged ONLY on CONFIRMED follows. With five or
    // more eligible businesses the bar is the documented target of
    // five. With FEWER than five the user is never trapped by the
    // catalogue size: their own honest selection IS the target — a
    // settled confirm with zero failures completes (spec: "any
    // honest selection can be confirmed").
    final confirmed = _rows
        .where((r) => r.status == _FollowPickStatus.confirmed)
        .length;
    final complete =
        confirmed > 0 &&
        (_rows.length >= _targetFollows
            ? confirmed >= _targetFollows
            : _failedCount == 0);
    if (complete) {
      setState(() => _done = true);
    }
  }

  /// Retry ONLY the failed requests. Confirmed rows are never touched
  /// — a retry can never undo or duplicate a successful follow.
  Future<void> _retryFailed() => _confirmSelection();

  String get _confirmLabel {
    final n = _selectedCount;
    return n == 0
        ? 'Follow businesses'
        : 'Follow $n ${n == 1 ? 'business' : 'businesses'}';
  }

  @override
  Widget build(BuildContext context) {
    // The SAME colors object every marketplace surface reads — light and
    // dark are pinned by tests through the theme provider.
    final sheetColors = ref.watch(themeProvider).colors;

    final maxH = MediaQuery.of(context).size.height * 0.85;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: sheetColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Follow businesses you care about.',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: sheetColors.textPrimary,
                      ),
                    ),
                  ),
                  // Maybe later: zero mutations, just close.
                  TextButton(
                    key: const ValueKey('follow-onboarding-sheet-later'),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Maybe later'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _rows.length < _targetFollows && !_loading && _loadError == null
                    ? 'Following a business puts its latest in your '
                          '"Your follows" rail. Few businesses are listed '
                          'yet — follow any you care about, or browse the '
                          'marketplace to discover more.'
                    : 'Following a business puts its latest in your '
                          '"Your follows" rail.',
                style: TextStyle(
                  fontSize: 13,
                  color: sheetColors.textSecondary,
                ),
              ),
            ),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  _loadError!,
                  key: const ValueKey('follow-onboarding-sheet-error'),
                  style: TextStyle(fontSize: 13, color: sheetColors.danger),
                ),
              ),
            Flexible(child: _body(sheetColors)),
          ],
        ),
      ),
    );
  }

  Widget _body(AzamanColors colors) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_rows.isEmpty) {
      // No eligible businesses at all: honest, never trapped.
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No businesses are listed yet.',
              key: const ValueKey('follow-onboarding-sheet-empty'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You can discover them as they join the marketplace.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _rows.length,
            itemBuilder: (context, i) {
              final row = _rows[i];
              return _pickRow(row, colors);
            },
          ),
        ),
        if (_failedCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(
              'Followed $_confirmedCount of ${_confirmedCount + _failedCount}'
              '${_done ? '' : ' — the rest can be retried.'}',
              key: const ValueKey('follow-onboarding-sheet-partial'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Row(
            children: [
              if (_selectedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '$_selectedCount selected',
                    key: const ValueKey('follow-onboarding-sheet-count'),
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ),
              Expanded(child: _confirmButton(colors)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _confirmButton(AzamanColors colors) {
    if (_done) {
      return FilledButton(
        key: const ValueKey('follow-onboarding-sheet-done'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(
          _confirmedCount == 1
              ? 'Following $_confirmedCount business — done'
              : 'Following $_confirmedCount businesses — done',
        ),
      );
    }
    if (_failedCount > 0) {
      final retry = FilledButton.tonal(
        key: const ValueKey('follow-onboarding-sheet-retry'),
        onPressed: _submitting || _anyPending ? null : _retryFailed,
        child: _submitting || _anyPending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text('Retry $_failedCount failed'),
      );
      // Spec: with fewer than five eligible businesses the user is
      // never trapped by a row that keeps failing — the discovery
      // fallback (browse the marketplace) is always offered. It is
      // an honest exit: confirmed follows are real and durable; the
      // failed rows simply remain unfollowed.
      if (_rows.length < _targetFollows) {
        return Row(
          children: [
            Expanded(child: retry),
            TextButton(
              key: const ValueKey('follow-onboarding-sheet-browse'),
              onPressed: _submitting || _anyPending
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Browse marketplace'),
            ),
          ],
        );
      }
      return retry;
    }
    final n = _selectedCount;
    return FilledButton(
      key: const ValueKey('follow-onboarding-sheet-confirm'),
      onPressed: _submitting || _anyPending || n == 0
          ? null
          : _confirmSelection,
      child: _submitting || _anyPending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(_confirmLabel),
    );
  }

  Widget _pickRow(_FollowPickRow row, AzamanColors colors) {
    final b = row.business;
    final cat = BusinessCategories.fromWire(b.category);
    final selectable = row.status == _FollowPickStatus.idle && !_submitting;
    return Semantics(
      button: true,
      label:
          '${b.businessName}, ${cat.label}'
          '${b.isVerified ? ', verified' : ''}'
          '${row.selected ? ', selected' : ''}',
      child: ListTile(
        key: ValueKey('follow-onboarding-pick-${b.id}'),
        onTap: selectable ? () => _toggleSelect(row) : null,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cat.color.withValues(alpha: 0.14),
            border: Border.all(color: cat.color, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: b.logoUrl != null && b.logoUrl!.isNotEmpty
              ? AzamanNetworkImage(
                  imageUrl: b.logoUrl!,
                  width: 42,
                  height: 42,
                  fit: BoxFit.cover,
                )
              : Icon(cat.icon, size: 20, color: cat.color),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                b.businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (b.isVerified)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.verified_rounded,
                  size: 15,
                  color: colors.accent,
                ),
              ),
          ],
        ),
        subtitle: Text(
          cat.label,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        trailing: _rowTrailing(row, colors),
      ),
    );
  }

  Widget _rowTrailing(_FollowPickRow row, AzamanColors colors) {
    switch (row.status) {
      case _FollowPickStatus.pending:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _FollowPickStatus.confirmed:
        return Icon(Icons.check_circle_rounded, color: colors.accent);
      case _FollowPickStatus.failed:
        return Icon(Icons.error_outline_rounded, color: colors.danger);
      case _FollowPickStatus.idle:
        return Checkbox(
          value: row.selected,
          onChanged: selectableRow(row) ? (v) => _toggleSelect(row) : null,
        );
    }
  }

  bool selectableRow(_FollowPickRow row) =>
      row.status == _FollowPickStatus.idle && !_submitting;
}

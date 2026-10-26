// =============================================================================
// AZAMAN — LAUNCHER DRAFTS (transient continuation, original programme §C)
//
// The problem this file solves: a user who begins work in a Home launcher
// window (Send, Withdraw, Add Cash, Convert) and closes or swipes it away
// currently loses every keystroke. This service gives a MEANINGFUL
// unsubmitted form a five-minute, user-scoped, expiring draft — a purely
// LOCAL convenience, never a server-confirmed transaction.
//
// INVARIANTS (review-enforced):
//   1. Drafts store ONLY the allowed editable inputs required to restore
//      the correct flow and stage. Never PINs, OTPs, biometric approvals,
//      tokens or secret credential material.
//   2. Every draft has ONE stable identity per (user, surface): repeated
//      close/Keep/reopen cycles UPDATE that record; they can never
//      duplicate continuation cards.
//   3. Expiry is five minutes from the stored save timestamp, enforced
//      against the WALL CLOCK whenever drafts are read — opening the
//      notification centre, returning to the foreground, or tapping
//      Resume. No on-screen countdown owns expiry: a draft saved and
//      left for ten minutes is already dead when next read, regardless
//      of whether the app stayed in the foreground.
//   4. Only an explicit Keep action renews expiry. Ordinary rebuilds and
//      list refreshes never extend a draft's life.
//   5. Drafts are scoped to the authenticated user and cleared on
//      logout/account switch.
//   6. Storage is the encrypted FlutterSecureStorage — recipient/account
//      data never sits in plain preferences for convenience.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The launcher surfaces that support transient drafts. Only unsubmitted
/// flows. A submitted transaction is NEVER a draft — its durable identity
/// and resolution stay with the server (§C.2).
enum LauncherSurface { send, withdraw, addCash, convert }

extension LauncherSurfaceX on LauncherSurface {
  String get wire => switch (this) {
        LauncherSurface.send => 'send',
        LauncherSurface.withdraw => 'withdraw',
        LauncherSurface.addCash => 'addCash',
        LauncherSurface.convert => 'convert',
      };

  String get label => switch (this) {
        LauncherSurface.send => 'Send',
        LauncherSurface.withdraw => 'Withdraw',
        LauncherSurface.addCash => 'Add Cash',
        LauncherSurface.convert => 'Convert',
      };

  String get actionLabel => switch (this) {
        LauncherSurface.send => 'Finish sending',
        LauncherSurface.withdraw => 'Finish withdrawing',
        LauncherSurface.addCash => 'Finish adding cash',
        LauncherSurface.convert => 'Finish converting',
      };

  /// The canonical route the Resume action navigates through — never a
  /// client-invented path.
  String get route => switch (this) {
        LauncherSurface.send => '/send',
        LauncherSurface.withdraw => '/withdraw',
        LauncherSurface.addCash => '/deposit',
        LauncherSurface.convert => '/convert',
      };

  static LauncherSurface? fromWire(String? wire) => switch (wire) {
        'send' => LauncherSurface.send,
        'withdraw' => LauncherSurface.withdraw,
        'addCash' => LauncherSurface.addCash,
        'convert' => LauncherSurface.convert,
        _ => null,
      };
}

/// How long a kept draft lives. Five minutes, per the original programme.
const Duration kLauncherDraftTtl = Duration(minutes: 5);

class LauncherDraft {
  /// Stable identity: one draft per (user, surface) — `'<surface>.<userId>'`.
  /// A re-Keep REPLACES the record under this id; duplicates are impossible
  /// by construction.
  final String id;

  final LauncherSurface surface;

  /// Wall-clock epoch millis of the LAST explicit Keep. Expiry is computed
  /// against this — see [isExpiredAt].
  final int savedAtMs;

  /// The allowed editable inputs only, e.g. amountRaw, entryIndex,
  /// reference. Interpretation belongs to the owning surface; nothing here
  /// ever rehydrates financial authority, balances or quotes.
  final Map<String, dynamic> payload;

  const LauncherDraft({
    required this.id,
    required this.surface,
    required this.savedAtMs,
    this.payload = const {},
  });

  /// Five minutes from the last Keep, judged by the passed clock so tests
  /// and callers share one definition of "now".
  bool isExpiredAt(int nowMs) =>
      nowMs - savedAtMs > kLauncherDraftTtl.inMilliseconds;

  /// Coarse, honest remaining-life label for the continuation card.
  String minutesLeftAt(int nowMs) {
    final left = ((savedAtMs + kLauncherDraftTtl.inMilliseconds - nowMs) /
            Duration.millisecondsPerMinute)
        .ceil();
    return left <= 0 ? 'expiring' : '${left}m left';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'surface': surface.wire,
        'savedAtMs': savedAtMs,
        'payload': payload,
      };

  static LauncherDraft? fromJson(Map<String, dynamic> json) {
    final surface = LauncherSurfaceX.fromWire(json['surface']?.toString());
    final id = json['id']?.toString();
    final savedAtMs = json['savedAtMs'];
    if (surface == null || id == null || savedAtMs is! int) return null;
    return LauncherDraft(
      id: id,
      surface: surface,
      savedAtMs: savedAtMs,
      payload: json['payload'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['payload'] as Map<String, dynamic>)
          : const {},
    );
  }

  LauncherDraft copyWith({int? savedAtMs, Map<String, dynamic>? payload}) =>
      LauncherDraft(
        id: id,
        surface: surface,
        savedAtMs: savedAtMs ?? this.savedAtMs,
        payload: payload ?? this.payload,
      );
}

class LauncherDraftsService {
  LauncherDraftsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'azm.launcher.drafts.';

  String _key(String userId) => '$_keyPrefix$userId';

  Future<List<LauncherDraft>> loadForUser(String userId) async {
    final raw = await _storage.read(key: _key(userId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final now = DateTime.now().millisecondsSinceEpoch;
      // EXPIRY IS ENFORCED AT READ: opening the notification centre (which
      // calls load) is one of the enforcement points. An expired draft is
      // removed here — it must never reappear as a continuation card.
      final alive = <LauncherDraft>[];
      var changed = false;
      for (final e in decoded) {
        final d = e is Map<String, dynamic> ? LauncherDraft.fromJson(e) : null;
        if (d == null) {
          changed = true;
          continue;
        }
        if (d.isExpiredAt(now)) {
          changed = true;
          continue;
        }
        alive.add(d);
      }
      if (changed) await _write(userId, alive);
      return alive;
    } catch (_) {
      // Corrupt blob: an unreadable draft is a dead draft. Honest absence,
      // never a crash at the notification centre's open.
      return const [];
    }
  }

  Future<void> _write(String userId, List<LauncherDraft> drafts) async {
    if (drafts.isEmpty) {
      await _storage.delete(key: _key(userId));
      return;
    }
    await _storage.write(
      key: _key(userId),
      value: jsonEncode([for (final d in drafts) d.toJson()]),
    );
  }

  /// Upsert by stable id. Only an explicit Keep reaches here — this is the
  /// single point that renews expiry.
  Future<void> keep(String userId, LauncherDraft draft) async {
    final drafts = [...await loadForUser(userId)];
    final i = drafts.indexWhere((d) => d.id == draft.id);
    if (i >= 0) {
      drafts[i] = draft;
    } else {
      drafts.add(draft);
    }
    await _write(userId, drafts);
  }

  /// Permanent discard — the swipe-away of a continuation card, or the
  /// "Discard draft" choice in the exit prompt.
  Future<void> discard(String userId, String draftId) async {
    final drafts = [...await loadForUser(userId)];
    drafts.removeWhere((d) => d.id == draftId);
    await _write(userId, drafts);
  }

  /// Logout / account switch: the next user must never inherit drafts.
  Future<void> clearAll(String userId) async {
    await _storage.delete(key: _key(userId));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider — the notification centre and the launcher surfaces share it.
// ─────────────────────────────────────────────────────────────────────────────

class LauncherDraftsState {
  /// The authenticated user the current draft list belongs to. Null until
  /// the first [LauncherDraftsController.loadForUser] — drafts are scoped;
  /// there is no cross-user bleed by construction.
  final String? userId;
  final List<LauncherDraft> drafts;

  const LauncherDraftsState({this.userId, this.drafts = const []});

  LauncherDraftsState copyWith({String? userId, List<LauncherDraft>? drafts}) =>
      LauncherDraftsState(
        userId: userId ?? this.userId,
        drafts: drafts ?? this.drafts,
      );
}

class LauncherDraftsController extends StateNotifier<LauncherDraftsState> {
  LauncherDraftsController(this._service) : super(const LauncherDraftsState());

  final LauncherDraftsService _service;

  /// GENERATION GUARD (review gap 4): every load and every invalidation
  /// bumps the generation; a storage read started under an older
  /// generation completes into the void instead of overwriting the
  /// active user's draft state. Covers direct account switching,
  /// session invalidation and explicit logout alike — cleanup can
  /// never be undone by an in-flight storage read.
  int _generation = 0;

  /// Stable identity for a (user, surface) pair — the id that makes
  /// repeated close/Keep/reopen cycles an UPSERT instead of a duplicate.
  static String draftId(String userId, LauncherSurface surface) =>
      '${surface.wire}.$userId';

  /// One of the three expiry-enforcement points: the notification centre's
  /// open calls this, and the service already drops expired records.
  Future<void> loadForUser(String? userId) async {
    final gen = ++_generation;
    if (userId == null || userId.isEmpty) {
      state = const LauncherDraftsState();
      return;
    }
    final drafts = await _service.loadForUser(userId);
    // A late completion from an older generation must not overwrite the
    // active user's state — the request was made for a user the session
    // has since left behind.
    if (gen != _generation) return;
    state = LauncherDraftsState(userId: userId, drafts: drafts);
  }

  /// Explicit Keep — the ONLY action that renews expiry.
  Future<void> keepDraft(LauncherDraft draft) async {
    final uid = state.userId;
    if (uid == null) return; // unauthenticated: nothing to persist
    await _service.keep(uid, draft);
    await loadForUser(uid);
  }

  /// Permanent discard of one draft. Swipe-away on a continuation card and
  /// the exit prompt's "Discard draft" both land here. The stored editable
  /// state is gone for the current user and cannot return on refresh.
  Future<void> discardDraft(String draftId) async {
    final uid = state.userId;
    if (uid == null) return;
    await _service.discard(uid, draftId);
    await loadForUser(uid);
  }

  /// Logout / session invalidation. Bumps the generation FIRST so an
  /// in-flight loadForUser cannot complete into state after the
  /// cleanup and resurrect the outgoing user's drafts. (Form drafts
  /// ARE deleted on logout — they are unsubmitted conveniences, unlike
  /// submitted-deposit continuations.)
  Future<void> clearForLogout() async {
    ++_generation;
    final uid = state.userId;
    state = const LauncherDraftsState();
    if (uid != null) await _service.clearAll(uid);
  }

  /// REVIEW FOLLOW-UP P1 — direct account switch (no logout). The
  /// outgoing user's in-memory drafts are dropped IMMEDIATELY —
  /// synchronously — so they can never render after the identity
  /// boundary, and the incoming user's drafts load under a fresh
  /// generation. The outgoing user's STORED drafts are NOT deleted by
  /// a switch: they are user-scoped and reload when that user signs
  /// back in (they still die on explicit logout, per the form-draft
  /// contract above).
  Future<void> switchToUser(String? userId) async {
    ++_generation;
    state = const LauncherDraftsState();
    await loadForUser(userId);
  }
}

/// The single draft authority. Every consumer — the exit prompt wiring, the
/// continuation cards, Resume, logout — watches this one provider.
final launcherDraftsProvider =
    StateNotifierProvider<LauncherDraftsController, LauncherDraftsState>(
  (ref) => LauncherDraftsController(LauncherDraftsService()),
);

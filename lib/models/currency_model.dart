import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';

/// The user's global preferred display currency.
///
/// SOURCE OF TRUTH (2026-10-20 reconciliation) — this notifier is the ONE
/// authority for the global display preference. The redundant second path
/// (SettingsProvider.defaultCurrency / 'default_currency' key) is retired;
/// every surface reads [currencyProvider].
///
/// GHANA-FIRST: a fresh/unset preference defaults to GHS.
///
/// MIGRATION RULE (safe, verified against the full lifecycle):
///   • The legacy key 'display_currency' was written ONLY by an explicit
///     user pick in Settings / the drawer picker (no code path ever wrote
///     a default value to it — the old notifier only READ its 'usdc'
///     fallback). A stored value is therefore always a DELIBERATE choice:
///     it is carried over verbatim and survives restart.
///   • No stored value at all → GHS default, and nothing is written until
///     the user actually chooses (unset stays "fresh", GHS-by-default).
///   • 'GHC' (obsolete cedi code) and other legacy spellings normalize
///     safely via [CurrencyCatalog.normalizeCode]; junk never silently
///     becomes USDC.
///
/// BACKEND BRIDGE (one-way push, honest about what exists):
///   An explicit change mirrors the canonical value to the existing
///   /users/preferences contract ('currencyDisplay'), so the backend copy
///   is truthful. We deliberately do NOT adopt a backend value on load:
///   historical 'currencyDisplay' values were polluted by the old
///   SettingsProvider default sync (it PUT 'currencyDisplay: USDC' on every
///   unrelated toggle save) and cannot be distinguished from intent, and
///   no surface ever displayed them — so there is no cross-device display
///   sync today, and none is claimed.
enum DisplayCurrency { ghs, usdc }

class CurrencyNotifier extends StateNotifier<DisplayCurrency> {
  static const _prefKey = 'display_currency';

  /// The preference is not loaded yet — callers that need certainty about
  /// a *fresh* vs *deliberate* state can await [ready].
  Future<void>? _ready;

  CurrencyNotifier() : super(DisplayCurrency.ghs) {
    _ready = _load();
  }

  Future<void> get ready => _ready ?? Future.value();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored == null) return; // fresh/unset → GHS default (no write)
    final normalized = _normalize(stored);
    if (normalized != null) {
      if (normalized != state) {
        state = normalized;
      }
      return;
    }
    // Unrecognized legacy junk: treat as unset (GHS default) and remove the
    // poisoned value so it cannot resurface.
    await prefs.remove(_prefKey);
  }

  Future<void> set(DisplayCurrency c) async {
    if (state != c) state = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, c.name);
    _pushToBackend(c);
  }

  static DisplayCurrency? _normalize(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'ghs':
      case 'ghc':
        return DisplayCurrency.ghs;
      case 'usdc':
      case 'usd':
        return DisplayCurrency.usdc;
      default:
        return null;
    }
  }

  /// Mirrors the canonical choice to the existing preferences contract.
  /// Fire-and-forget like every other preference sync in the app; the
  /// local key remains authoritative either way.
  Future<void> _pushToBackend(DisplayCurrency c) async {
    try {
      await apiClient.put('/users/preferences', {
        'preferences': {
          'currencyDisplay': c == DisplayCurrency.ghs ? 'GHS' : 'USDC',
        },
      });
    } catch (_) {
      // The backend mirror is best-effort; the local preference is the
      // authority and persistence is already complete.
    }
  }
}

final currencyProvider =
    StateNotifierProvider<CurrencyNotifier, DisplayCurrency>(
      (ref) => CurrencyNotifier(),
    );

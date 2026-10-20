// =============================================================================
// AZAMAN — CURRENCY CATALOG (GHS-first, 2026-10-20)
//
// ONE typed description of every currency the product actually supports.
// The wheel, the display preference and the Send composer all read from
// here — no screen invents its own currency list, symbol or precision.
//
// GHANA-FIRST: GHS is the default primary display currency. USDC is the
// settlement rail and remains a first-class *choice* — never a silent
// default. 'GHC' is the obsolete code for the cedi; it is accepted on
// read (normalized to GHS) and never written.
//
// THREE DISTINCT CONCEPTS (never conflate):
//   1. the user's global preferred DISPLAY currency  (CurrencyNotifier)
//   2. the unit of the CURRENT input amount           (the wheel, local)
//   3. the currency actually sent/settled by a rail   (e.g. USDC for the
//      peer-transfer rail — GHS inputs are CONVERTED to a reviewed USDC
//      amount before the wire; the GHS number alone never travels)
// =============================================================================

/// Metadata for one supported currency. No conversion logic lives here —
/// conversion is [CurrencyMath]'s job, driven by a validated rate snapshot.
class AzCurrency {
  /// Canonical ISO-style code. 'GHS' — never 'GHC' — and 'USDC'.
  final String code;

  /// User-facing symbol ('GH₵', 'USDC').
  final String symbol;

  /// Human label for pickers and screen readers.
  final String label;

  /// Input precision of the amount-entry field (minor-unit digits).
  final int inputDecimals;

  /// Precision the peer-transfer wire contract accepts for this unit.
  final int wireDecimals;

  const AzCurrency({
    required this.code,
    required this.symbol,
    required this.label,
    this.inputDecimals = 2,
    this.wireDecimals = 2,
  });

  @override
  bool operator ==(Object other) => other is AzCurrency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// The catalog. ONLY currencies with a real backend contract are listed —
/// future assets (BTC etc.) are deliberately absent until the app has the
/// rate support, balance model and wire contract for them.
abstract final class CurrencyCatalog {
  static const ghs = AzCurrency(
    code: 'GHS',
    symbol: 'GH₵',
    label: 'Ghana Cedi',
    inputDecimals: 2,
    wireDecimals: 2,
  );

  static const usdc = AzCurrency(
    code: 'USDC',
    symbol: 'USDC',
    label: 'USD Coin',
    inputDecimals: 2,
    wireDecimals: 2,
  );

  /// Currencies available to an amount-entry wheel on a surface whose rail
  /// supports both (the Send composer: GHS input is converted to a reviewed
  /// USDC wire amount; USDC input is the wire amount).
  static const List<AzCurrency> sendEntryUnits = [ghs, usdc];

  /// Normalizes a stored/legacy currency string to a catalog code, or null
  /// when it maps to nothing supported. 'GHC' (obsolete cedi code) safely
  /// normalizes to 'GHS'; unknown junk normalizes to null — callers then
  /// fall back to the GHS default rather than guessing USDC.
  static String? normalizeCode(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'GHS':
      case 'GHC':
      case 'CEDIS':
      case 'CEDIS_SYMBOL':
        return 'GHS';
      case 'USDC':
      case 'USD':
        return 'USDC';
      default:
        return null;
    }
  }

  /// Lookup by normalized code.
  static AzCurrency? byCode(String? raw) {
    final code = normalizeCode(raw);
    if (code == 'GHS') return ghs;
    if (code == 'USDC') return usdc;
    return null;
  }
}

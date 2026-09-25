import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DisplayCurrency { usdc, ghs }

class CurrencyNotifier extends StateNotifier<DisplayCurrency> {
  CurrencyNotifier() : super(DisplayCurrency.usdc) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('display_currency') ?? 'usdc';
    state = s == 'ghs' ? DisplayCurrency.ghs : DisplayCurrency.usdc;
  }

  Future<void> set(DisplayCurrency c) async {
    state = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('display_currency', c.name);
  }
}

final currencyProvider =
    StateNotifierProvider<CurrencyNotifier, DisplayCurrency>(
  (ref) => CurrencyNotifier(),
);

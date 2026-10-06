// =============================================================================
// EXPERIENCE PASS §3 — dark is the DEFAULT, but default != forced.
//
// A missing preference and an explicit choice are DIFFERENT states:
//   • no saved preference        => dark   (the new default)
//   • explicitly saved light (0) => light  (a deliberate choice always wins)
//   • explicitly saved dark  (1) => dark
//   • legacy midnight (2)        => dark   (existing migration stays safe)
//   • corrupt out-of-range       => dark   (falls back to the default)
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';

void main() {
  test('missing preference => dark (the default)', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.currentTheme, AzamanTheme.dark);
  });

  test('explicitly saved light => light (default != forced)', () async {
    SharedPreferences.setMockInitialValues({'azaman_theme': 0});
    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.currentTheme, AzamanTheme.light);
  });

  test('explicitly saved dark => dark', () async {
    SharedPreferences.setMockInitialValues({'azaman_theme': 1});
    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.currentTheme, AzamanTheme.dark);
  });

  test('legacy midnight (2) migrates safely to dark', () async {
    SharedPreferences.setMockInitialValues({'azaman_theme': 2});
    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.currentTheme, AzamanTheme.dark);
  });

  test('corrupt out-of-range value falls back to the dark default', () async {
    SharedPreferences.setMockInitialValues({'azaman_theme': 99});
    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.currentTheme, AzamanTheme.dark);
  });
}

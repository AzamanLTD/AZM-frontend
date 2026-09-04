import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('dine-in tab screen has lifecycle-safe authoritative refresh', () {
    final source = File('lib/screens/marketplace/dinein_tab_screen.dart').readAsStringSync();

    expect(source, contains("with WidgetsBindingObserver"));
    expect(source, contains("Timer.periodic(const Duration(seconds: 10)"));
    expect(source, contains("WidgetsBinding.instance.addObserver(this)"));
    expect(source, contains("_refreshTimer?.cancel()"));
    expect(source, contains("WidgetsBinding.instance.removeObserver(this)"));
    expect(source, contains("AppLifecycleState.resumed"));
    expect(source, contains("ref.invalidate(dineInTabProvider(widget.tabId))"));
  });
}

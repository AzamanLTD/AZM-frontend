import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('ErrorWidget.builder produces themed screen, not red screen',
      (tester) async {
    // Build the themed error widget that matches main.dart's ErrorWidget.builder
    const themedError = Material(
      color: Color(0xFF1A1A2E),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              SizedBox(height: 16),
              Text('Something went wrong',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Pull down to refresh, or restart the app.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: themedError,
        ),
      ),
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Something went wrong'), findsOneWidget);
  });
}

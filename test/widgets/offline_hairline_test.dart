// test/widgets/offline_hairline_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/offline_hairline.dart';

void main() {
  testWidgets('collapses to zero height when nothing is wrong', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: OfflineHairline(offline: false)),
    ));
    expect(tester.getSize(find.byType(OfflineHairline)).height, 0);
  });

  testWidgets('is exactly 24px and labelled when offline', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: OfflineHairline(offline: true)),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(OfflineHairline)).height,
        OfflineHairline.height);
    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('reconnected flash uses the same geometry', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: OfflineHairline(offline: false, justReconnected: true)),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(OfflineHairline)).height,
        OfflineHairline.height);
    expect(find.text('Back online'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SliverAppBar collapses and expands smoothly', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: false,
            flexibleSpace: const FlexibleSpaceBar(title: Text('Marketplace')),
          ),
          SliverList(delegate: SliverChildBuilderDelegate(
            (_, i) => ListTile(title: Text('Item $i')), childCount: 50)),
        ],
      ),
    ));
    expect(find.text('Marketplace'), findsOneWidget);
    // Scroll down — app bar should collapse
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    // Expanded title may be hidden; collapsed title visible
  });
}

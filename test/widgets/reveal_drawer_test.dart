// The reveal drawer: the page slides aside to show a drawer that lives
// underneath it. Opening, closing, system back, and closing from inside.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/widgets/settings/az_reveal_drawer.dart';

Widget _host(AzRevealDrawerController c, {Widget? drawer}) => MaterialApp(
      home: AzRevealDrawer(
        controller: c,
        drawer: drawer ?? const Material(child: Center(child: Text('the drawer'))),
        child: const Scaffold(body: Center(child: Text('the page'))),
      ),
    );

/// A drawer row that closes through the scope, then reports it navigated.
class _RowThatNavigates extends StatelessWidget {
  const _RowThatNavigates({required this.onNavigate});
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) => Material(
        child: Center(
          child: TextButton(
            onPressed: () {
              AzRevealDrawerScope.maybeOf(context)!.close();
              onNavigate();
            },
            child: const Text('go'),
          ),
        ),
      );
}

void main() {
  testWidgets('closed: the drawer is not built into the hit/semantics tree', (tester) async {
    final c = AzRevealDrawerController();
    await tester.pumpWidget(_host(c));
    expect(c.isOpen, isFalse);
    expect(find.text('the drawer'), findsNothing); // offstage
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('the controller opens it and the page slides left by the drawer width', (tester) async {
    final c = AzRevealDrawerController();
    await tester.pumpWidget(_host(c));
    final before = tester.getCenter(find.text('the page'));
    c.open();
    await tester.pumpAndSettle();
    expect(c.isOpen, isTrue);
    expect(find.text('the drawer'), findsOneWidget);
    final after = tester.getCenter(find.text('the page'));
    expect(before.dx - after.dx, greaterThan(250), reason: 'the page travelled left');
  });

  testWidgets('a drag from the right edge opens; a drag back closes', (tester) async {
    final c = AzRevealDrawerController();
    await tester.pumpWidget(_host(c));
    final size = tester.getSize(find.byType(AzRevealDrawer));
    await tester.dragFrom(Offset(size.width - 6, size.height / 2), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(c.isOpen, isTrue);

    // Drag the visible strip of the page back to the right.
    await tester.dragFrom(Offset(20, size.height / 2), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(c.isOpen, isFalse);
  });

  testWidgets('system back closes the drawer instead of leaving the app', (tester) async {
    final c = AzRevealDrawerController();
    await tester.pumpWidget(_host(c));
    c.open();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(c.isOpen, isFalse);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('a row inside the drawer closes it through the scope, never by popping a route', (tester) async {
    final c = AzRevealDrawerController();
    var navigated = false;
    await tester.pumpWidget(_host(c, drawer: _RowThatNavigates(onNavigate: () => navigated = true)));
    c.open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(navigated, isTrue);
    expect(c.isOpen, isFalse);
    expect(find.text('the page'), findsOneWidget, reason: 'the shell route is still there');
  });

  testWidgets('reduced motion snaps open and closed', (tester) async {
    final c = AzRevealDrawerController();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _host(c),
    ));
    c.open();
    await tester.pump();
    expect(c.isOpen, isTrue);
    c.close();
    await tester.pump();
    expect(c.isOpen, isFalse);
  });
}

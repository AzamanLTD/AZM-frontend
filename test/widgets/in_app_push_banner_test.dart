import 'package:azaman/widgets/in_app_push_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows an explicit View action when a notification is actionable', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            const SizedBox.expand(),
            InAppPushBanner(
              title: 'Order ready',
              body: 'Your meal can be collected.',
              onTap: () => tapped = true,
              onDismiss: () {},
            ),
          ],
        ),
      ),
    );

    await tester.pump();
    expect(find.text('View'), findsOneWidget);
    expect(find.byTooltip('Dismiss notification'), findsOneWidget);

    await tester.tap(find.text('View'));
    expect(tapped, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('remains directly visible when animations are disabled', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Stack(
            children: [
              const SizedBox.expand(),
              InAppPushBanner(
                title: 'Notice',
                body: 'A new update is available.',
                onDismiss: () {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Notice'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

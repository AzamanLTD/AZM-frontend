// test/widgets/az_error_surface_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/az_error_surface.dart';
import 'package:azaman/widgets/az_state_illustration.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeProvider.getThemeData(AzamanTheme.light),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders message + hint', (tester) async {
    await tester.pumpWidget(_wrap(const AzErrorSurface(
      message: 'This part of Azaman did not load.',
      hint: 'Your data is safe.',
    )));
    expect(find.text('This part of Azaman did not load.'), findsOneWidget);
    expect(find.text('Your data is safe.'), findsOneWidget);
  });

  testWidgets('retry fires once and the surface never claims success',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_wrap(AzErrorSurface(
      message: 'Could not load your trades.',
      onRetry: () => calls++,
    )));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('success', findRichText: true), findsNothing);
  });

  testWidgets('continue-offline only exists when the callback does',
      (tester) async {
    await tester.pumpWidget(_wrap(const AzErrorSurface(message: 'x')));
    expect(find.text('Continue offline'), findsNothing);

    await tester.pumpWidget(
        _wrap(AzErrorSurface(message: 'x', onContinueOffline: () {})));
    expect(find.text('Continue offline'), findsOneWidget);
  });

  testWidgets('fromFramework uses designed copy, not raw error text',
      (tester) async {
    await tester.pumpWidget(_wrap(AzErrorSurface.fromFramework()));
    expect(find.byType(AzStateIllustration), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
  });

  testWidgets('the scene redraws when progress changes', (tester) async {
    final colors = ThemeProvider.getColors(AzamanTheme.light);
    await tester.pumpWidget(_wrap(
        AzStateIllustration(scene: AzStateScene.error, colors: colors, progress: 0.0)));
    final before = tester
        .widget<AzStateIllustration>(find.byType(AzStateIllustration))
        .progress;
    await tester.pumpWidget(_wrap(
        AzStateIllustration(scene: AzStateScene.error, colors: colors, progress: 1.0)));
    final after = tester
        .widget<AzStateIllustration>(find.byType(AzStateIllustration))
        .progress;
    expect(before, 0.0);
    expect(after, 1.0);
  });
}

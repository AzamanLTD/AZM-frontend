// Visual record: the shared profile header — someone else's profile and
// your own — light and dark, with real fonts.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/profile/az_profile_header.dart';

bool _loaded = false;
Future<void> _fonts() async {
  if (_loaded) return;
  for (final e in {
    'Inter': 'assets/fonts/Inter-Variable.ttf',
    'MaterialIcons': 'test/goldens/fonts/MaterialIcons-Regular.otf',
    'DejaVuSans': 'test/goldens/fonts/DejaVuSans.ttf',
  }.entries) {
    final bytes = await File(e.value).readAsBytes();
    await (FontLoader(e.key)..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)))).load();
  }
  _loaded = true;
}

Widget _other(AzamanColors c) => AzProfileHeader(
      seed: 4,
      name: 'Ama Mensah',
      handle: '@ama',
      verified: true,
      onBack: () {},
      trailing: const SizedBox(width: 44),
      chips: [
        const AzProfileChip(icon: Icons.handshake_outlined, label: 'Friends since Mar 2026'),
        AzProfileChip(icon: Icons.verified_outlined, label: 'Verified', tone: c.success),
      ],
      stats: const [
        AzProfileStat(value: '12', label: 'Completed'),
        AzProfileStat(value: '4.8', label: 'Rating'),
        AzProfileStat(value: '3', label: 'Mutual'),
      ],
      actions: [
        AzProfileAction(label: 'Send', icon: Icons.arrow_upward_rounded, primary: true, onTap: () {}),
        AzProfileAction(label: 'Message', icon: Icons.chat_bubble_outline_rounded, onTap: () {}),
      ],
    );

Widget _own(AzamanColors c) => AzProfileHeader(
      seed: 7,
      name: 'Kofi Boateng',
      handle: '@kofi',
      verified: true,
      subtitle: 'Waakye in the morning, trotro at night.',
      chips: const [
        AzProfileChip(icon: Icons.calendar_today_outlined, label: 'Member since Jan 2026'),
        AzProfileChip(icon: Icons.local_fire_department_outlined, label: '9-day streak'),
      ],
      stats: const [
        AzProfileStat(value: '27', label: 'Trades'),
        AzProfileStat(value: '4.9', label: 'Rating'),
        AzProfileStat(value: '9', label: 'Day streak'),
      ],
      actions: [
        AzProfileAction(label: 'Edit profile', icon: Icons.edit_outlined, primary: true, onTap: () {}),
        AzProfileAction(label: '', icon: Icons.qr_code_2_rounded, onTap: () {}),
      ],
    );

void main() {
  for (final dark in [false, true]) {
    for (final which in ['other', 'own']) {
      testWidgets('profile header — $which ${dark ? 'dark' : 'light'}', (tester) async {
        SharedPreferences.setMockInitialValues({'azaman_theme': dark ? 1 : 0});
        final tp = ThemeProvider();
        await tester.runAsync(() async {
          await _fonts();
          for (var i = 0; i < 100 && !tp.isLoaded; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        });
        tester.view
          ..physicalSize = const Size(360, 560) * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final base = ThemeProvider.getThemeData(dark ? AzamanTheme.dark : AzamanTheme.light);
        await tester.pumpWidget(ProviderScope(
          overrides: [themeProvider.overrideWith((ref) => tp)],
          child: MediaQuery(
            data: const MediaQueryData(size: Size(360, 560), padding: EdgeInsets.only(top: 24), disableAnimations: true),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: base.copyWith(textTheme: base.textTheme.apply(fontFamilyFallback: const ['DejaVuSans'])),
              home: Scaffold(
                backgroundColor: tp.colors.background,
                body: RepaintBoundary(child: which == 'other' ? _other(tp.colors) : _own(tp.colors)),
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(find.byType(Scaffold),
            matchesGoldenFile('../goldens/profile/${which}_${dark ? 'dark' : 'light'}.png'));
      });
    }
  }
}

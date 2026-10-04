import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/widgets/chat_unread_badge.dart';
import 'package:azaman/widgets/inbox/inbox_entry.dart';
import 'package:azaman/widgets/inbox/inbox_row.dart';

Future<void> _pump(WidgetTester tester, InboxEntry entry, {VoidCallback? onTap}) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: InboxRow(entry: entry, onTap: onTap ?? () {}, now: DateTime(2026, 10, 10, 12))),
    ),
  ));
  // Badge/avatar entrance animations (flutter_animate) must finish before teardown.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unread friend row: badge, mention marker, money glyph, time', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      InboxEntry(
        kind: InboxKind.friend,
        id: 'f1',
        title: 'kofi',
        preview: 'sent you 20 @ama',
        lastAt: DateTime(2026, 10, 10, 9),
        unread: 2,
        mentioned: true,
        signal: InboxSignal.moneyIn,
        friendId: 7,
      ),
      onTap: () => taps++,
    );
    expect(find.text('kofi'), findsOneWidget);
    expect(find.byType(ChatUnreadBadge), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox_row_mention')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox_signal_moneyIn')), findsOneWidget);
    expect(find.text('3h'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inbox_row_friend_f1')));
    expect(taps, 1);
  });

  testWidgets('read row has no badge and shows the placeholder preview', (tester) async {
    await _pump(tester, const InboxEntry(kind: InboxKind.friend, id: 'f2', title: 'ama'));
    expect(find.byType(ChatUnreadBadge), findsNothing);
    expect(find.text('Start chatting...'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox_row_mention')), findsNothing);
  });

  testWidgets('group row with active Susu shows the ring and glyph', (tester) async {
    final g = GroupSummary(
      id: 'g1',
      name: 'Market Mamas',
      status: 'ACTIVE',
      susuGroupId: 's1',
      susuStatus: 'ACTIVE',
      members: const [],
      updatedAt: DateTime(2026, 10, 1),
    );
    await _pump(tester, InboxEntry.fromGroup(g));
    expect(find.text('Market Mamas'), findsOneWidget);
    expect(find.byKey(const ValueKey('group_susu_ring_active')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox_signal_susuActive')), findsOneWidget);
    expect(find.text('0 members'), findsOneWidget);
  });
}
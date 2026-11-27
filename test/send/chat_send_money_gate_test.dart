// Every way into the Send composer passes the money gate.
//
// The /send route wraps SendMoneyScreen in MoneyRouteGuard, but a chat opens
// the composer with a direct push, outside the router. That push skipped the
// gate until 2026-11-27: a locked member could land on a live composer from a
// conversation. This pins the rule at the source: any direct construction of
// the chat-seeded composer sits inside a MoneyRouteGuard.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every SendMoneyScreen.toFriend construction is wrapped in MoneyRouteGuard', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('SendMoneyScreen.toFriend(')) continue;
        if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('///')) continue;
        if (entity.path.replaceAll('\\', '/').endsWith('lib/screens/send_money_screen.dart')) continue;
        final window = lines.sublist((i - 4).clamp(0, lines.length), i + 1).join('\n');
        if (!window.contains('MoneyRouteGuard(')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a chat-seeded Send must pass the same money lock as /send');
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Shell socket lifecycle permanent guard (milestone 2026-09-30 hardening):
/// MainWrapper deregisters its shell socket callbacks from dispose() via a
/// service cached in initState. deactivate() must never own deregistration
/// (it fires on temporary removals and never re-registers on re-insertion),
/// and dispose() must never call ref.read (riverpod asserts once the element
/// is disposed). This is a source-contract guard, in the repo's established
/// source-scan style.
void main() {
  test(
    'MainWrapper deregisters socket callbacks from dispose(), not deactivate()',
    () {
      final source = File('lib/main.dart').readAsStringSync();

      // The service is cached in a late final field, assigned in initState.
      expect(source, contains('late final SocketService _shellSocketService;'));
      expect(
        source,
        contains('_shellSocketService = ref.read(socketServiceProvider);'),
        reason:
            'the socket service must be cached in initState, when ref is legal',
      );

      // No deactivate() override anywhere in the shell.
      expect(
        source,
        isNot(contains('void deactivate()')),
        reason:
            'deactivate() fires for temporary removals and never re-registers '
            'on re-insertion; it must not own deregistration',
      );

      // dispose() deregisters all three shell listeners via the cached service.
      final disposeStart = source.indexOf('void dispose()');
      expect(disposeStart, greaterThan(0));
      final disposeEnd = source.indexOf('super.dispose();', disposeStart);
      expect(disposeEnd, greaterThan(disposeStart));
      final disposeBody = source
          .substring(disposeStart, disposeEnd)
          .replaceAll(RegExp(r'//[^\n]*'), ''); // comments may mention ref.read
      expect(
        disposeBody,
        contains('_shellSocketService.removeNewTradeRequestListener();'),
      );
      expect(
        disposeBody,
        contains('_shellSocketService.removeBizNotificationListener();'),
      );
      expect(
        disposeBody,
        contains(
          '_shellSocketService.removeBizNotificationsUpdatedListener();',
        ),
      );

      // dispose() never touches ref (riverpod asserts once the element is disposed).
      expect(disposeBody, isNot(contains('ref.read')));
      expect(disposeBody, isNot(contains('ref.watch')));

      // No stray legacy deregistration path remains outside dispose().
      expect(
        source.indexOf('removeNewTradeRequestListener();'),
        greaterThan(0),
      );
      expect(
        source.lastIndexOf('removeNewTradeRequestListener();'),
        lessThan(disposeEnd),
        reason: 'every deregistration must live inside dispose()',
      );
      expect(
        source.lastIndexOf('removeBizNotificationListener();'),
        lessThan(disposeEnd),
        reason: 'every deregistration must live inside dispose()',
      );
      expect(
        source.lastIndexOf('removeBizNotificationsUpdatedListener();'),
        lessThan(disposeEnd),
        reason: 'every deregistration must live inside dispose()',
      );
    },
  );

  test(
    'AUDIT §3: switching shell tabs closes the + launcher before the '
    'page transition starts',
    () {
      final source = File('lib/main.dart').readAsStringSync();

      // The handler is _onNavItemSelected; the launcher close must be
      // INSIDE it, before the transition controller fires.
      final fnStart = source.indexOf('void _onNavItemSelected(int i) {');
      expect(fnStart, greaterThan(0), reason: 'the tab-select handler exists');
      final fnEnd = source.indexOf('void ', fnStart + 10);
      final body = source.substring(
          fnStart, fnEnd > 0 ? fnEnd : source.length);

      expect(body, contains('if (_plus.isOpen) _plus.close();'),
          reason: 'the shared launcher controller is closed on every '
              'genuine tab switch');

      // The close happens BEFORE the transition animation is armed —
      // the overlay never rides a mid-flight page transition.
      final closeAt = body.indexOf('_plus.close()');
      final transitionAt = body.indexOf('_transitionCtrl.forward(from: 0)');
      expect(closeAt, greaterThan(0));
      expect(transitionAt, greaterThan(0));
      expect(closeAt, lessThan(transitionAt),
          reason: 'close precedes the transition animation');

      // And only on a genuine switch — the same-tab early return above
      // the close keeps re-taps inert.
      final returnAt = body.indexOf('if (i == _selectedIndex) return;');
      expect(returnAt, greaterThan(0));
      expect(returnAt, lessThan(closeAt),
          reason: 'same-tab taps return before touching the launcher');
    },
  );
}

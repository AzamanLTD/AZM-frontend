// =============================================================================
// AZAMAN — DEMO CHAT SEND REGRESSION ("the generic Chat failure")
//
// Reported symptom: in the demo build, sending a message in a chat
// always shows a FAILED bubble with a retry chip, and friend chats show
// nothing at all — a generic failure with no visible cause.
//
// Root cause (traced 2026-10-21): the demo socket never connects
// (SocketService is a no-op in demo mode by design), so every send falls
// through PremiumChatNotifier._emitSendEvent -> _sendViaHttp -> HTTP
// POST. DemoInterceptor._matchPost had NO handler for the chat send
// routes, so the catch-all returned the generic {'data': {'ok': true}}
// envelope. The real backend answers 201 { success: true, message: {...} }.
// _sendViaHttp reads decoded['message']; finding none it marks the
// optimistic bubble FAILED. Hence: every demo send fails generically.
//
// This suite pins the fix — the demo must answer the chat send routes
// with the REAL backend contract so the optimistic row is upgraded to
// a server-canonical message instead of failing.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/config.dart';
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/models/chat_message.dart';
import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/premium_chat_provider.dart';
import 'package:azaman/services/socket_service.dart';

User _demoUser() => User(
      id: DemoSeedData.demoUserId,
      username: DemoSeedData.demoUsername,
      email: 'pyrax@demo.azaman.app',
      token: DemoSeedData.demoToken,
      role: 'USER',
      azmBalance: 12450.00,
      availableBalance: 12450.00,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppConfig.enableDemoMode();
    // Demo mode never connects a socket — this is exactly the production
    // demo configuration under which the failure was reported.
    SocketService.instance.rawSocketForTesting = null;
  });

  group('demo friend chat send', () {
    test('a text send is acknowledged with a server id, not failed', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(authProvider).setUser(_demoUser());

      const params = ChatContextParams(
        context: ChatContext.friend,
        contextId: '101',
      );
      // autoDispose family — hold a listener so the notifier survives
      // across the awaits below.
      final sub = container.listen(
        premiumChatProvider(params),
        (_, __) {},
      );
      final notifier = container.read(premiumChatProvider(params).notifier);
      await Future<void>.delayed(
          const Duration(milliseconds: 200)); // loadMessages resolves
      await notifier.sendTextMessage('See you at Republic Bar');

      // Drain the HTTP round-trip (demo interceptor answers immediately).
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final state = sub.read();
      expect(state.messages, isNotEmpty,
          reason: 'the optimistic row must exist');
      final msg = state.messages.first;
      expect(msg.text, 'See you at Republic Bar');
      expect(msg.status, MessageStatus.sent,
          reason:
              'the demo must answer the send with the REAL backend '
              'contract (201 {success: true, message: {...}}) so the '
              'optimistic row is acknowledged, never generically failed.');
      expect(msg.id, isNot(msg.localId),
          reason: 'the ack must upgrade the row with the server id');
    });
  });

  group('demo group chat send', () {
    test('a text send is acknowledged with a server id, not failed', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(authProvider).setUser(_demoUser());

      const params = ChatContextParams(
        context: ChatContext.group,
        contextId: 'grp-1',
      );
      final sub = container.listen(
        premiumChatProvider(params),
        (_, __) {},
      );
      final notifier = container.read(premiumChatProvider(params).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await notifier.sendTextMessage('Rolling out — who is in?');

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final state = sub.read();
      final msg = state.messages.first;
      expect(msg.text, 'Rolling out — who is in?');
      expect(msg.status, MessageStatus.sent,
          reason: 'group sends ride the same contract.');
      expect(msg.id, isNot(msg.localId));
    });
  });
}

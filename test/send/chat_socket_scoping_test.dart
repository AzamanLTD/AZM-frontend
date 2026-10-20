// =============================================================================
// AZAMAN — CHAT SOCKET LISTENER SCOPING REGRESSION (PR #165 review finding 3)
//
// One closed chat screen must never deafen the rest of the app:
//   • the chat screen removes ONLY the exact callbacks it registered
//     (`socket.off(event, handler)`) — a bare `socket.off(event)` would
//     also strip FriendProvider's `friend_message` listener (shared
//     unread/message state) and any other component's listener;
//   • it must not LEAK its own listeners after dispose either.
//
// The socket is a REAL socket_io_client socket created with
// `autoConnect: false` — no network is ever attempted; the in-memory
// listener registry is the entire surface under test.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/user_model.dart';
import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/friend_provider.dart';
import 'package:azaman/screens/friends/friend_chat_screen.dart';
import 'package:azaman/services/socket_service.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class _FixedAuth extends AuthProvider {
  _FixedAuth(this.sessionUser);
  final User sessionUser;
  @override
  User? get user => sessionUser;
  @override
  Future<void> fetchUserDetails() async {}
}

class _FakeFriends extends FriendProvider {
  _FakeFriends(super.ref) {
    friends = [];
    isLoading = false;
  }
  @override
  Future<void> refreshAll() async {}
}

User _user() => User(
      id: '7',
      username: 'me',
      email: 'me@example.com',
      token: 'tok',
      role: 'USER',
      azamanId: 'AZM-999999999',
      availableBalance: 50.0,
    );

io.Socket _offlineSocket() {
  // autoConnect:false — the manager never opens an engine, no network.
  return io.io('http://127.0.0.1:9',
      io.OptionBuilder().build()..['autoConnect'] = false);
}

Widget _app() => ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FixedAuth(_user())),
        friendProvider.overrideWith((ref) => _FakeFriends(ref)),
      ],
      child: const MaterialApp(home: FriendChatScreen(
        friendshipId: 'fs-77',
        friendUsername: 'ama',
        friendId: 101,
      )),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // Never leak the offline socket into other tests.
    SocketService.instance.rawSocketForTesting = null;
  });

  testWidgets(
      'dispose removes ONLY the chat screen\'s own listeners — another '
      'component\'s listener on the SAME event survives',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async {
      if (call.method == 'read') return 'mock-token';
      return null;
    });
    SharedPreferences.setMockInitialValues({'azaman_theme': 1});

    final socket = _offlineSocket();
    SocketService.instance.rawSocketForTesting = socket;

    // Simulate FriendProvider: it owns its OWN friend_message and
    // friend_typing listeners, independent of any chat screen.
    var externalMessages = 0;
    var externalTyping = 0;
    socket.on('friend_message', (_) => externalMessages++);
    socket.on('friend_typing', (_) => externalTyping++);

    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));
    // The chat screen registered its own listeners on the same events.
    expect(socket.hasListeners('friend_message'), isTrue);
    expect(socket.hasListeners('friend_typing'), isTrue);

    // Leave the chat (the screen unmounts → dispose runs).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));

    // The external listeners SURVIVE the chat screen's dispose — a bare
    // socket.off(event) would have stripped them too.
    expect(socket.hasListeners('friend_message'), isTrue,
        reason: 'FriendProvider\'s message listener must survive');
    expect(socket.hasListeners('friend_typing'), isTrue,
        reason: 'an unrelated component\'s typing listener must survive');
    expect(externalMessages, 0, reason: 'never fired in this test');
    expect(externalTyping, 0);

    // io.io() caches its manager per URL — without an explicit dispose
    // the two externally-registered listeners persist into the next
    // test's socket registry (same cache) and break its premise.
    socket.dispose();
  });

  testWidgets(
      'dispose leaves NO screen-owned handlers behind — every listener '
      'that remains belongs to the app, not the dead screen', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async {
      if (call.method == 'read') return 'mock-token';
      return null;
    });
    SharedPreferences.setMockInitialValues({'azaman_theme': 1});

    final socket = _offlineSocket();
    SocketService.instance.rawSocketForTesting = socket;

    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));
    expect(socket.hasListeners('friend_typing'), isTrue,
        reason: 'the screen (and the premium chat notifier) subscribed');
    expect(socket.hasListeners('message_ack'), isTrue,
        reason: 'the premium chat notifier subscribed');
    expect(socket.hasListeners('ticket_presence_update'), isTrue);
    expect(socket.hasListeners('ticket_status_changed'), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));

    // The chat screen's OWN handlers and the auto-disposed premium chat
    // notifier's handlers are ALL gone — no other subscriber exists in
    // this test, so every one of these events must be listener-free.
    expect(socket.hasListeners('friend_typing'), isFalse,
        reason: 'the dead screen\'s typing handler came off');
    expect(socket.hasListeners('message_ack'), isFalse,
        reason: 'the disposed notifier\'s handler came off');
    expect(socket.hasListeners('ticket_presence_update'), isFalse);
    expect(socket.hasListeners('ticket_status_changed'), isFalse);
    expect(socket.hasListeners('friend_message'), isFalse,
        reason: 'no app-global listener was registered in this test — '
            'EVERY friend_message handler belonged to the dead screen or '
            'its disposed notifier');
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/data/demo_seed_data.dart';
import 'package:azaman/data/demo_interceptor.dart';

void main() {
  group('DemoSeedData', () {
    test('authMe returns user with correct fields', () {
      final data = DemoSeedData.authMe();
      expect(data['user'], isNotNull);
      expect(data['user']['id'], 1);
      expect(data['user']['username'], 'Pyrax');
      expect(data['user']['azamanId'], 'AZM-000123456');
      expect(data['user']['kycStatus'], 'VERIFIED');
      expect(data['user']['availableBalance'], 12450.00);
    });

    test('friends returns 3 friends', () {
      final friends = DemoSeedData.friends();
      expect(friends.length, 3);
      expect(friends[0]['friend']['username'], 'Bella');
      expect(friends[1]['friend']['username'], 'Lamar');
      expect(friends[2]['friend']['username'], 'Ibrah');
    });

    test('friendMessages returns messages for known friendshipId', () {
      final msgs = DemoSeedData.friendMessages('101');
      expect(msgs['messages'], isNotNull);
      expect((msgs['messages'] as List).length, 4);
      final transfer = (msgs['messages'] as List).firstWhere(
        (m) => m['messageType'] == 'PEER_TRANSFER',
      );
      expect(transfer['metadata']['amount'], 150.00);
    });

    test('groupChats returns 2 groups', () {
      final groups = DemoSeedData.groupChats();
      expect(groups.length, 2);
      expect(groups[0]['name'], contains('Friday'));
      expect(groups[1]['susuGroupId'], isNotNull);
    });

    test('p2pAds returns 4 ads', () {
      final ads = DemoSeedData.p2pAds();
      expect(ads['ads'], isNotNull);
      expect((ads['ads'] as List).length, 4);
    });

    test('storiesFeed returns 3 groups', () {
      final feed = DemoSeedData.storiesFeed();
      expect(feed['groups'], isNotNull);
      expect((feed['groups'] as List).length, 3);
    });

    test('vaults returns 1 vault with yield', () {
      final vaults = DemoSeedData.vaults();
      expect(vaults['data'], isNotNull);
      expect((vaults['data'] as List).length, 1);
      expect((vaults['data'] as List).first['yieldEnabled'], true);
    });

    test('susuGroups returns 1 active susu', () {
      final susu = DemoSeedData.susuGroups();
      expect(susu['data'], isNotNull);
      expect((susu['data'] as List).length, 1);
      expect((susu['data'] as List).first['status'], 'ACTIVE');
    });

    test('leaderboard returns 5 entries with demo user at rank 1', () {
      final board = DemoSeedData.leaderboard();
      expect(board['data']['entries'], isNotNull);
      final entries = board['data']['entries'] as List;
      expect(entries.length, 5);
      expect(entries[0]['username'], 'Pyrax');
      expect(entries[0]['rank'], 1);
    });

    test('azmSummary has staking tier GOLD', () {
      final summary = DemoSeedData.azmSummary();
      expect(summary['data']['stakingTier'], 'GOLD');
      expect(summary['data']['loginStreak'], 7);
    });

    test('savingsOverview has 2 goals', () {
      final savings = DemoSeedData.savingsOverview();
      expect(savings['data']['goals'], isNotNull);
      expect((savings['data']['goals'] as List).length, 2);
    });

    test('notifications returns 3 unread', () {
      final notifs = DemoSeedData.notifications();
      expect((notifs['data'] as List).length, 3);
    });

    test('storefrontDiscover returns 3 businesses', () {
      final store = DemoSeedData.storefrontDiscover();
      expect((store['data'] as List).length, 3);
    });

    test('cardSkins returns 4 skins with one equipped', () {
      final skins = DemoSeedData.cardSkins();
      final list = skins['data'] as List;
      expect(list.length, 4);
      final equipped = list.where((s) => s['equipped'] == true);
      expect(equipped.length, 1);
    });
  });

  group('DemoInterceptor', () {
    test('tryGet returns 200 for /friends', () {
      final resp = DemoInterceptor.tryGet('/friends');
      expect(resp, isNotNull);
      expect(resp!.statusCode, 200);
      final body = jsonDecode(resp.body);
      expect(body['friends'], isNotNull);
    });

    test('tryGet returns 200 for /auth/me/1', () {
      final resp = DemoInterceptor.tryGet('/auth/me/1');
      expect(resp, isNotNull);
      expect(resp!.statusCode, 200);
      final body = jsonDecode(resp.body);
      expect(body['user']['username'], 'Pyrax');
    });

    test('tryGet returns 200 for /friends/chat/101/messages', () {
      final resp = DemoInterceptor.tryGet('/friends/chat/101/messages');
      expect(resp, isNotNull);
      final body = jsonDecode(resp!.body);
      expect(body['messages'], isNotNull);
      expect((body['messages'] as List).length, 4);
    });

    test('tryGet returns 200 for /group-chats/grp-1/messages', () {
      final resp = DemoInterceptor.tryGet('/group-chats/grp-1/messages');
      expect(resp, isNotNull);
      final body = jsonDecode(resp!.body);
      expect((body['messages'] as List).length, 4);
    });

    test('tryGet returns 200 for /oracle/rates', () {
      final resp = DemoInterceptor.tryGet('/oracle/rates');
      expect(resp, isNotNull);
      final body = jsonDecode(resp!.body);
      expect(body['data']['liveUsdToGhs'], 15.42);
    });

    test('tryGet returns 200 for /p2p/ads', () {
      final resp = DemoInterceptor.tryGet('/p2p/ads');
      expect(resp, isNotNull);
      final body = jsonDecode(resp!.body);
      expect((body['ads'] as List).length, 4);
    });

    test('tryGet returns 200 for /stories/feed', () {
      final resp = DemoInterceptor.tryGet('/stories/feed');
      expect(resp, isNotNull);
      final body = jsonDecode(resp!.body);
      expect((body['groups'] as List).length, 3);
    });

    test('tryPost returns 200 for stories view', () {
      final resp = DemoInterceptor.tryPost('/stories/s-1/view', {});
      expect(resp, isNotNull);
      expect(resp!.statusCode, 200);
    });

    // ── Chat send routes: the REAL backend contract, not okSuccess ─────
    // The generic POST fallback once made every demo chat send fail
    // (the generic Chat failure); these pin the 201 {success, message}
    // envelope PremiumChatNotifier._sendViaHttp upgrades the optimistic
    // bubble with.
    test('tryPost answers a friend-chat send with the 201 message envelope',
        () {
      final resp = DemoInterceptor.tryPost('/friends/chat/101/messages', {
        'content': 'Demo hello',
        'messageType': 'TEXT',
        'metadata': {'amount': 25.0, 'currency': 'GHS'},
      });
      expect(resp, isNotNull);
      expect(resp!.statusCode, 201);
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      expect(body['success'], true);
      final msg = body['message'] as Map<String, dynamic>;
      expect(msg['id'], isNotEmpty);
      expect(msg['id'].toString(), startsWith('fm-demo-'));
      expect(msg['createdAt'], isNotNull);
      expect(msg['friendshipId'], '101');
      expect(msg['senderId'], 1);
      expect(msg['content'], 'Demo hello');
      expect(msg['messageType'], 'TEXT');
      final meta = msg['metadata'] as Map<String, dynamic>;
      expect(meta['amount'], 25.0);
      // The receiver is the real peer on friendship 101 (Bella), not a
      // fabricated id.
      expect(msg['receiverId'], 2);
    });

    test('tryPost echoes reply metadata for a friend-chat send', () {
      final resp = DemoInterceptor.tryPost('/friends/chat/102/messages', {
        'content': 'answering you',
        'messageType': 'TEXT',
        'replyToId': 'm102-1',
        'replyToText': 'earlier',
        'replyToSenderName': 'Lamar',
      });
      final body = jsonDecode(resp!.body) as Map<String, dynamic>;
      final msg = body['message'] as Map<String, dynamic>;
      expect(msg['replyToId'], 'm102-1');
      expect(msg['replyToText'], 'earlier');
      expect(msg['replyToSenderName'], 'Lamar');
      // Friendship 102's peer is Lamar (id 3).
      expect(msg['receiverId'], 3);
    });

    test('tryPost answers a group-chat send with the 201 message envelope',
        () {
      final resp = DemoInterceptor.tryPost('/group-chats/grp-1/messages', {
        'type': 'TEXT',
        'content': 'Group hello',
        'media': {
          'url': 'https://cdn.example/v.mp4',
          'type': 'VIDEO',
          'mimeType': 'video/mp4',
          'size': 1024,
          'duration': 8,
          'waveformPeaks': [1, 2, 3],
        },
      });
      expect(resp, isNotNull);
      expect(resp!.statusCode, 201);
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      expect(body['success'], true);
      final msg = body['message'] as Map<String, dynamic>;
      expect(msg['id'], isNotEmpty);
      expect(msg['groupId'], 'grp-1');
      expect(msg['senderId'], 1);
      expect(msg['type'], 'TEXT');
      expect(msg['content'], 'Group hello');
      // The nested media body is flattened exactly the way the real
      // groupChatService returns it, so a reload parses the same row.
      expect(msg['mediaUrl'], 'https://cdn.example/v.mp4');
      expect(msg['mediaType'], 'VIDEO');
      expect(msg['mediaMimeType'], 'video/mp4');
      expect(msg['mediaSize'], 1024);
      expect(msg['mediaDuration'], 8);
      expect((msg['mediaWaveformPeaks'] as List).length, 3);
    });

    test('tryPut returns 200', () {
      final resp = DemoInterceptor.tryPut('/users/preferences', {});
      expect(resp, isNotNull);
      expect(resp!.statusCode, 200);
    });

    test('tryPatch returns 200', () {
      final resp = DemoInterceptor.tryPatch('/users/profile');
      expect(resp, isNotNull);
      expect(resp!.statusCode, 200);
    });

    test('tryDelete returns 200', () {
      final resp = DemoInterceptor.tryDelete('/friends/101');
      expect(resp, isNotNull);
      expect(resp!.statusCode, 200);
    });

    test('tryGet handles unknown endpoints gracefully', () {
      final resp = DemoInterceptor.tryGet('/some/unknown/endpoint');
      expect(resp, isNotNull);
      expect(resp!.statusCode, 200);
      final body = jsonDecode(resp.body);
      expect(body['data'], []);
    });
  });
}

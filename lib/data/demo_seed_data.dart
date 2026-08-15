// =============================================================================
// AZAMAN — DEMO SEED DATA
//
// Comprehensive mock data for demo mode. Every endpoint the app calls
// is intercepted by DemoInterceptor (in api_client.dart) and served
// from these maps. Data is realistic: Ghanaian names, GHS currency,
// real-looking AZM IDs, plausible balances, timestamps within the last
// few days, etc.
//
// The demo user is "Pyrax Mensah" (AZM-000123456), a verified user with
// 12,450 AZM balance, 3 friends, 2 group chats, 4 marketplace ads,
// 2 savings goals, 1 active vault, 1 active susu, and a leaderboard rank.
// =============================================================================

class DemoSeedData {
  DemoSeedData._();

  // ── Demo User ─────────────────────────────────────────────────────────
  static const String demoUserId = '1';
  static const String demoUsername = 'Pyrax';
  static const String demoToken = 'demo-token-not-real';

  // ── /auth/me/{id} ─────────────────────────────────────────────────────
  static Map<String, dynamic> authMe() => {
    'user': {
      'id': 1,
      'username': demoUsername,
      'email': 'pyrax@demo.azaman.app',
      'role': 'USER',
      'profilePictureUrl': 'https://i.pravatar.cc/150?img=8',
      'azamanId': 'AZM-000123456',
      'availableBalance': 12450.00,
      'vendorUnallocatedBalance': 0,
      'escrowLockedBalance': 350.00,
      'disputeEscrowBalance': 0,
      'azmBalance': 12450.00,
      'kycStatus': 'VERIFIED',
      'banStatus': 'ACTIVE',
    }
  };

  // ── /users/dashboard ──────────────────────────────────────────────────
  static Map<String, dynamic> dashboard() => {
    'data': {
      'totalBalance': 12450.00,
      'availableBalance': 12450.00,
      'escrowLocked': 350.00,
      'azmBalance': 12450.00,
      'yellowCardRate': 15.42,
      'ghsEquivalent': 192045.90,
    },
  };

  // ── /users/preferences ────────────────────────────────────────────────
  static Map<String, dynamic> preferences() => {
    'data': {
      'theme': 'system',
      'vendorTagEnabled': true,
      'shortcuts': ['deposit', 'withdraw', 'send', 'susu'],
      'notifications': {
        'trades': true,
        'messages': true,
        'marketing': false,
      },
    },
  };

  // ── /users/onboarding ────────────────────────────────────────────────
  static Map<String, dynamic> onboarding() => {
    'data': {'completed': true}
  };

  // ── /friends ─────────────────────────────────────────────────────────
  static List<Map<String, dynamic>> friends() => [
    {
      'friendshipId': 101,
      'friend': {
        'id': 2,
        'username': 'Bella',
        'profilePictureUrl': 'https://i.pravatar.cc/150?img=47',
      },
      'latestMessage': {
        'content': 'Hey Pyrax! Are we still on for Friday?',
        'createdAt': _hoursAgo(2),
        'messageType': 'TEXT',
      },
      'unreadCount': 3,
    },
    {
      'friendshipId': 102,
      'friend': {
        'id': 3,
        'username': 'Lamar',
        'profilePictureUrl': 'https://i.pravatar.cc/150?img=53',
      },
      'latestMessage': {
        'content': 'Sent you the GHS 200 for the susu',
        'createdAt': _hoursAgo(5),
        'messageType': 'TEXT',
      },
      'unreadCount': 0,
    },
    {
      'friendshipId': 103,
      'friend': {
        'id': 4,
        'username': 'Ibrah',
        'profilePictureUrl': 'https://i.pravatar.cc/150?img=68',
      },
      'latestMessage': {
        'content': '',
        'createdAt': _hoursAgo(28),
        'messageType': 'IMAGE',
        'mediaUrl': 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400',
      },
      'unreadCount': 1,
    },
  ];

  // ── /friends/chat/{id}/messages ──────────────────────────────────────
  static Map<String, dynamic> friendMessages(String friendshipId) {
    switch (friendshipId) {
      case '101':
        return {
          'messages': [
            {
              'id': 'm101-1',
              'senderId': 2,
              'senderUsername': 'Bella',
              'content': 'Hey Pyrax! Are we still on for Friday?',
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(2),
              'status': 'DELIVERED',
            },
            {
              'id': 'm101-2',
              'senderId': 1,
              'senderUsername': demoUsername,
              'content': 'Yes! 6pm at Republic Bar right?',
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(1, 55),
              'status': 'READ',
            },
            {
              'id': 'm101-3',
              'senderId': 2,
              'senderUsername': 'Bella',
              'content': "Perfect! Don't forget to bring the speaker",
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(1, 50),
              'status': 'DELIVERED',
            },
            {
              'id': 'm101-4',
              'senderId': 2,
              'senderUsername': 'Bella',
              'content': '',
              'messageType': 'PEER_TRANSFER',
              'content': 'For the speaker rental',
              'metadata': {
                'amount': 150.00,
                'currency': 'GHS',
                'type': 'sent',
                'reference': 'AZM-TXN-001',
              },
              'createdAt': _hoursAgo(1, 45),
              'status': 'DELIVERED',
            },
          ],
          'hasMore': false,
        };
      case '102':
        return {
          'messages': [
            {
              'id': 'm102-1',
              'senderId': 3,
              'senderUsername': 'Lamar',
              'content': "Bro, the susu this month - I'll pay on Monday",
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(6),
              'status': 'READ',
            },
            {
              'id': 'm102-2',
              'senderId': 1,
              'senderUsername': demoUsername,
              'content': "No worries, I've got you covered",
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(5, 50),
              'status': 'READ',
            },
            {
              'id': 'm102-3',
              'senderId': 3,
              'senderUsername': 'Lamar',
              'content': 'Sent you the GHS 200 for the susu',
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(5),
              'status': 'READ',
            },
            {
              'id': 'm102-4',
              'senderId': 3,
              'senderUsername': 'Lamar',
              'content': '',
              'messageType': 'PEER_TRANSFER',
              'content': 'Susu contribution - August',
              'metadata': {
                'amount': 200.00,
                'currency': 'GHS',
                'type': 'received',
                'reference': 'AZM-TXN-002',
              },
              'createdAt': _hoursAgo(4, 55),
              'status': 'READ',
            },
          ],
          'hasMore': false,
        };
      case '103':
        return {
          'messages': [
            {
              'id': 'm103-1',
              'senderId': 4,
              'senderUsername': 'Ibrah',
              'content': 'Check out this place I found for the team meetup!',
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(28),
              'status': 'DELIVERED',
            },
            {
              'id': 'm103-2',
              'senderId': 4,
              'senderUsername': 'Ibrah',
              'content': '',
              'messageType': 'IMAGE',
              'mediaUrl': 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400',
              'createdAt': _hoursAgo(27, 55),
              'status': 'DELIVERED',
            },
            {
              'id': 'm103-3',
              'senderId': 1,
              'senderUsername': demoUsername,
              'content': '',
              'messageType': 'PEER_TRANSFER',
              'content': 'Team meetup deposit',
              'metadata': {
                'amount': 75.00,
                'currency': 'GHS',
                'type': 'sent',
                'reference': 'AZM-TXN-003',
              },
              'createdAt': _hoursAgo(27),
              'status': 'READ',
            },
            {
              'id': 'm103-4',
              'senderId': 4,
              'senderUsername': 'Ibrah',
              'content': 'Perfect! That covers the venue. Thank you!',
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(26, 30),
              'status': 'DELIVERED',
            },
          ],
          'hasMore': false,
        };
      default:
        return {'messages': [], 'hasMore': false};
    }
  }

  // ── /friends/chat/conversations ────────────────────────────────────
  static Map<String, dynamic> personalChatConversations() => {
    'success': true,
    'chats': [
      {
        'id': 'chat-1',
        'contactId': 3,
        'contactAzamanId': 'AZM-000000003',
        'contactName': 'ama_serwaa',
        'lastMessage': 'Hey! Are we still on for Friday?',
        'lastMessageTime': _hoursAgo(2),
        'unreadCount': 2,
      },
      {
        'id': 'chat-2',
        'contactId': 5,
        'contactAzamanId': 'AZM-000000005',
        'contactName': 'Alfred',
        'lastMessage': 'Sent you the GHS 150 for lunch 🙏',
        'lastMessageTime': _hoursAgo(8),
        'unreadCount': 0,
      },
      {
        'id': 'chat-3',
        'contactId': 7,
        'contactAzamanId': 'AZM-000000007',
        'contactName': 'kofi_danku',
        'lastMessage': 'The USDT rate is looking good today',
        'lastMessageTime': _hoursAgo(26),
        'unreadCount': 0,
      },
    ],
  };

  // ── /friends/requests ────────────────────────────────────────────────
  static Map<String, dynamic> friendRequests() => {
    'success': true,
    'total': 1,
    'requests': [
      {
        'id': 201,
        'fromUser': {
          'id': 5,
          'username': 'Alfred',
          'profilePictureUrl': 'https://i.pravatar.cc/150?img=12',
        },
        'requester': {
          'id': 5,
          'username': 'Alfred',
          'profilePictureUrl': 'https://i.pravatar.cc/150?img=15',
        },
        'createdAt': _hoursAgo(12),
        'status': 'PENDING',
      },
    ],
  };

  // ── /friends/chat/unread-count ───────────────────────────────────────
  static Map<String, dynamic> unreadCount() => {'unreadCount': 4};

  // ── /group-chats ─────────────────────────────────────────────────────
  static List<Map<String, dynamic>> groupChats() => [
    {
      'id': 'grp-1',
      'name': 'Friday Squad',
      'description': 'Weekend plans and chill',
      'avatarUrl': null,
      'status': 'ACTIVE',
      'susuGroupId': null,
      'susuStatus': null,
      'members': [
        {'id': 1, 'userId': 1, 'user': {'username': demoUsername, 'profilePictureUrl': 'https://i.pravatar.cc/150?img=47'}, 'role': 'ADMIN'},
        {'id': 2, 'userId': 2, 'user': {'username': 'Bella', 'profilePictureUrl': 'https://i.pravatar.cc/150?img=53'}, 'role': 'MEMBER'},
        {'id': 3, 'userId': 3, 'user': {'username': 'Lamar', 'profilePictureUrl': 'https://i.pravatar.cc/150?img=68'}, 'role': 'MEMBER'},
        {'id': 4, 'userId': 4, 'user': {'username': 'Ibrah', 'profilePictureUrl': 'https://i.pravatar.cc/150?img=12'}, 'role': 'MEMBER'},
      ],
      'updatedAt': _hoursAgo(1),
    },
    {
      'id': 'grp-2',
      'name': 'Susu Circle - August',
      'description': 'Monthly rotational savings group',
      'avatarUrl': null,
      'status': 'ACTIVE',
      'susuGroupId': 'susu-1',
      'susuGroup': {'status': 'ACTIVE', 'initiationDeadline': null},
      'members': [
        {'id': 1, 'userId': 1, 'user': {'username': demoUsername, 'profilePictureUrl': 'https://i.pravatar.cc/150?img=15'}, 'role': 'ADMIN'},
        {'id': 3, 'userId': 3, 'user': {'username': 'Lamar', 'profilePictureUrl': 'https://i.pravatar.cc/150?img=47'}, 'role': 'MEMBER'},
        {'id': 5, 'userId': 5, 'user': {'username': 'Alfred', 'profilePictureUrl': 'https://i.pravatar.cc/150?img=53'}, 'role': 'MEMBER'},
        {'id': 6, 'userId': 6, 'user': {'username': 'adwoa_boateng', 'profilePictureUrl': 'https://i.pravatar.cc/150?img=68'}, 'role': 'MEMBER'},
      ],
      'updatedAt': _hoursAgo(3),
    },
  ];

  // ── /group-chats/{id}/messages ───────────────────────────────────────
  static Map<String, dynamic> groupMessages(String groupId) {
    switch (groupId) {
      case 'grp-1':
        return {
          'messages': [
            {
              'id': 'g1-1',
              'senderId': 2,
              'senderUsername': 'Bella',
              'content': "Who's bringing the Jollof?",
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(3),
              'status': 'READ',
            },
            {
              'id': 'g1-2',
              'senderId': 3,
              'senderUsername': 'Lamar',
              'content': 'I got the drinks covered',
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(2, 45),
              'status': 'READ',
            },
            {
              'id': 'g1-3',
              'senderId': 1,
              'senderUsername': demoUsername,
              'content': "I'll bring the speaker and playlist",
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(2, 30),
              'status': 'READ',
            },
            {
              'id': 'g1-4',
              'senderId': 4,
              'senderUsername': 'Ibrah',
              'content': 'Legend!',
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(1),
              'status': 'READ',
            },
          ],
          'hasMore': false,
        };
      case 'grp-2':
        return {
          'messages': [
            {
              'id': 'g2-1',
              'senderId': 1,
              'senderUsername': demoUsername,
              'content': 'Susu cycle 2 starts Monday! Everyone ready?',
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(24),
              'status': 'READ',
            },
            {
              'id': 'g2-2',
              'senderId': 3,
              'senderUsername': 'Lamar',
              'content': "Ready! I'll pay Monday morning",
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(20),
              'status': 'READ',
            },
            {
              'id': 'g2-3',
              'senderId': 6,
              'senderUsername': 'adwoa_boateng',
              'content': 'Same here. Thanks for organizing this',
              'messageType': 'TEXT',
              'createdAt': _hoursAgo(5),
              'status': 'READ',
            },
          ],
          'hasMore': false,
        };
      default:
        return {'messages': [], 'hasMore': false};
    }
  }

  // ── /oracle/rates ─────────────────────────────────────────────────────
  static Map<String, dynamic> oracleRates() => {
    'success': true,
    'data': {
      'liveUsdToGhs': 15.42,
      'liveRetailRate': 15.38,
      'liveCorporateRate': 15.45,
      'rateSource': 'YELLOWCARD',
      'lastSync': _minutesAgo(3),
    },
  };

  // ── /trades/active ───────────────────────────────────────────────────
  static Map<String, dynamic> activeTrades() => {
    'trades': [
      {
        'id': 'trade-1',
        'status': 'IN_PROGRESS',
        'amountFiat': 1542.00,
        'amountCrypto': 100.00,
        'vendorUsername': 'crypto_gh',
        'isDisputed': false,
      },
    ],
  };

  // ── /trades/history ──────────────────────────────────────────────────
  static Map<String, dynamic> tradeHistory() => {
    'success': true,
    'history': [
      {
        'id': 'trade-1',
        'status': 'IN_PROGRESS',
        'amountFiat': 1542.00,
        'amountCrypto': 100.00,
        'vendorUsername': 'crypto_gh',
        'createdAt': _hoursAgo(20),
        'iAmVendor': false,
      },
      {
        'id': 'trade-2',
        'status': 'COMPLETED',
        'amountFiat': 771.00,
        'amountCrypto': 50.00,
        'vendorUsername': 'pay_fast',
        'createdAt': _hoursAgo(72),
        'iAmVendor': false,
      },
      {
        'id': 'trade-3',
        'status': 'COMPLETED',
        'amountFiat': 308.40,
        'amountCrypto': 20.00,
        'vendorUsername': 'crypto_gh',
        'createdAt': _hoursAgo(120),
        'iAmVendor': false,
      },
    ],
  };

  // ── /wallet/history ──────────────────────────────────────────────────
  static Map<String, dynamic> walletHistory() => {
    'success': true,
    'history': [
      {
        'id': 'w-1',
        'type': 'WITHDRAWAL',
        'amount': 500.00,
        'currency': 'GHS',
        'status': 'PENDING',
        'payoutMethod': 'MOMO',
        'network': 'MTN',
        'createdAt': _hoursAgo(4),
      },
      {
        'id': 'w-2',
        'type': 'DEPOSIT',
        'amount': 200.00,
        'currency': 'USDC',
        'status': 'COMPLETED',
        'createdAt': _hoursAgo(48),
      },
      {
        'id': 'w-3',
        'type': 'PEER_TRANSFER',
        'amount': 150.00,
        'currency': 'GHS',
        'status': 'COMPLETED',
        'createdAt': _hoursAgo(72),
      },
    ],
  };

  // ── /finance/transactions ────────────────────────────────────────────
  static Map<String, dynamic> financeTransactions() => {
    'data': [
      {
        'id': 't-1',
        'type': 'DEPOSIT_CRYPTO',
        'amount': 200.00,
        'currency': 'USDC',
        'status': 'COMPLETED',
        'createdAt': _hoursAgo(48),
        'description': 'Polygon USDC deposit',
      },
      {
        'id': 't-2',
        'type': 'WITHDRAWAL',
        'amount': 500.00,
        'currency': 'GHS',
        'status': 'PENDING',
        'createdAt': _hoursAgo(4),
        'description': 'MTN MoMo withdrawal',
      },
      {
        'id': 't-3',
        'type': 'TRADE',
        'amount': 1542.00,
        'currency': 'GHS',
        'status': 'IN_PROGRESS',
        'createdAt': _hoursAgo(20),
        'description': 'P2P trade with crypto_gh',
      },
    ],
  };

  // ── /notifications ──────────────────────────────────────────────────
  static Map<String, dynamic> notifications() => {
    'data': [
      {
        'id': 'n-1',
        'type': 'TRADE',
        'title': 'Trade in progress',
        'body': 'Your trade with crypto_gh is now in progress',
        'read': false,
        'createdAt': _hoursAgo(18),
      },
      {
        'id': 'n-2',
        'type': 'FRIEND_REQUEST',
        'title': 'New friend request',
        'body': 'Alfred wants to be your friend',
        'read': false,
        'createdAt': _hoursAgo(12),
      },
      {
        'id': 'n-3',
        'type': 'MESSAGE',
        'title': 'New message',
        'body': 'Bella: Hey Pyrax! Are we still on for Friday?',
        'read': false,
        'createdAt': _hoursAgo(2),
      },
    ],
  };

  // ── /notifications/unread-count ─────────────────────────────────────
  static Map<String, dynamic> unreadNotifications() => {'success': true, 'count': 3};

  // ── /savings/overview ───────────────────────────────────────────────
  static Map<String, dynamic> savingsOverview() => {
    'data': {
      'totalSavedGhs': 3200.00,
      'goals': [
        {
          'id': 'g-1',
          'name': 'New Laptop',
          'currentAmountGhs': 1800.00,
          'targetAmountGhs': 3500.00,
          'frequency': 'WEEKLY',
        },
        {
          'id': 'g-2',
          'name': 'Accra Trip',
          'currentAmountGhs': 1400.00,
          'targetAmountGhs': 2000.00,
          'frequency': 'MONTHLY',
        },
      ],
    },
  };

  // ── /vaults ──────────────────────────────────────────────────────────
  static Map<String, dynamic> vaults() => {
    'data': [
      {
        'id': 'v-1',
        'name': 'Emergency Fund',
        'balance': 2000.00,
        'currency': 'GHS',
        'lockedUntil': _daysFromNow(30),
        'apy': 8.5,
        'yieldEnabled': true,
        'autoRule': null,
      },
    ],
  };

  // ── /susu/me ─────────────────────────────────────────────────────────
  static Map<String, dynamic> susuGroups() => {
    'data': [
      {
        'id': 'susu-1',
        'name': 'Susu Circle - August',
        'status': 'ACTIVE',
        'contributionAmount': 200.00,
        'currency': 'GHS',
        'cycle': 2,
        'totalCycles': 4,
        'memberCount': 4,
        'nextPayoutUser': 'Lamar',
        'nextPayoutDate': _daysFromNow(7),
        'createdAt': _hoursAgo(240),
      },
    ],
  };

  // ── /azm/summary ─────────────────────────────────────────────────────
  static Map<String, dynamic> azmSummary() => {
    'data': {
      'azmBalance': 12450.00,
      'totalEarned': 1860.00,
      'totalSpent': 410.00,
      'stakingTier': 'GOLD',
      'stakingApy': 12.5,
      'loginStreak': 7,
      'rewardsAvailable': 45.00,
    },
  };

  // ── /azm/rates ───────────────────────────────────────────────────────
  static Map<String, dynamic> azmRates() => {
    'data': {
      'azmToGhs': 1.0,
      'azmToUsd': 0.0649,
      'lastUpdated': _minutesAgo(5),
    },
  };

  // ── /azm/friends-leaderboard ─────────────────────────────────────────
  static Map<String, dynamic> leaderboard() => {
    'data': {
      'entries': [
        {'userId': 1, 'username': demoUsername, 'azmBalance': 12450.00, 'rank': 1},
        {'userId': 2, 'username': 'Bella', 'azmBalance': 8200.00, 'rank': 2},
        {'userId': 5, 'username': 'Alfred', 'azmBalance': 5600.00, 'rank': 3},
        {'userId': 3, 'username': 'Lamar', 'azmBalance': 4300.00, 'rank': 4},
        {'userId': 6, 'username': 'adwoa_boateng', 'azmBalance': 2100.00, 'rank': 5},
      ],
    },
  };

  // ── /azm/spend/options ──────────────────────────────────────────────
  static Map<String, dynamic> spendOptions() => {
    'data': [
      {'id': 'airtime', 'label': 'Airtime', 'icon': 'phone'},
      {'id': 'data', 'label': 'Data Bundle', 'icon': 'wifi'},
      {'id': 'electricity', 'label': 'Electricity', 'icon': 'bolt'},
      {'id': 'water', 'label': 'Water', 'icon': 'water_drop'},
    ],
  };

  // ── /azm/spend/card-skins ───────────────────────────────────────────
  static Map<String, dynamic> cardSkins() => {
    'data': [
      {'id': 'default', 'name': 'Classic Gold', 'price': 0, 'owned': true, 'equipped': true},
      {'id': 'midnight', 'name': 'Midnight', 'price': 50, 'owned': true, 'equipped': false},
      {'id': 'sunset', 'name': 'Sunset', 'price': 100, 'owned': false, 'equipped': false},
      {'id': 'ocean', 'name': 'Ocean Depth', 'price': 150, 'owned': false, 'equipped': false},
    ],
  };

  // ── /p2p/ads ─────────────────────────────────────────────────────────
  static Map<String, dynamic> p2pAds() => {
    'ads': [
      {
        'id': 'ad-1',
        'vendorUsername': 'crypto_gh',
        'vendorId': '10',
        'type': 'SELL',
        'pricePerUSD': 15.42,
        'minLimit': 50,
        'maxLimit': 500,
        'availableUsdc': 2000.00,
        'paymentMethod': 'ZELLE',
        'queueFull': false,
        'queueDepth': 1,
        'completedTrades': 145,
        'completionRate': 0.98,
        'aiScore': 0.92,
        'isOnline': true,
        'lastSeen': _minutesAgo(5),
        'terms': 'Zelle only. Fast release within 10 minutes.',
      },
      {
        'id': 'ad-2',
        'vendorUsername': 'pay_fast',
        'vendorId': '11',
        'type': 'SELL',
        'pricePerUSD': 15.45,
        'minLimit': 20,
        'maxLimit': 300,
        'availableUsdc': 800.00,
        'paymentMethod': 'CASHAPP',
        'queueFull': false,
        'queueDepth': 0,
        'completedTrades': 89,
        'completionRate': 0.95,
        'aiScore': 0.88,
        'isOnline': true,
        'lastSeen': _minutesAgo(2),
        'terms': 'CashApp only. No third-party payments.',
      },
      {
        'id': 'ad-3',
        'vendorUsername': 'quick_trade',
        'vendorId': '12',
        'type': 'BUY',
        'pricePerUSD': 15.38,
        'minLimit': 30,
        'maxLimit': 200,
        'availableUsdc': 500.00,
        'paymentMethod': 'APPLE_PAY',
        'queueFull': false,
        'queueDepth': 0,
        'completedTrades': 56,
        'completionRate': 0.97,
        'aiScore': 0.85,
        'isOnline': false,
        'lastSeen': _hoursAgo(1),
        'terms': 'Buying USDC. Quick payment via Apple Pay.',
      },
      {
        'id': 'ad-4',
        'vendorUsername': 'crypto_gh',
        'vendorId': '10',
        'type': 'BUY',
        'pricePerUSD': 15.40,
        'minLimit': 100,
        'maxLimit': 1000,
        'availableUsdc': 5000.00,
        'paymentMethod': 'US_BANK_TRANSFER',
        'queueFull': false,
        'queueDepth': 2,
        'completedTrades': 145,
        'completionRate': 0.98,
        'aiScore': 0.91,
        'isOnline': true,
        'lastSeen': _minutesAgo(5),
        'terms': 'US bank transfer only. Chase, BofA, Wells Fargo.',
      },
    ],
  };

  // ── /ads/mine (vendor dashboard — the demo user's own P2P ads) ──────
  static Map<String, dynamic> myAds() => {
    'ads': [
      {
        'id': 1,
        'type': 'SELL',
        'crypto': 'USDT',
        'pricePerUSD': 15.42,
        'margin': 2.8,
        'minLimit': 50,
        'maxLimit': 500,
        'paymentMethod': 'ZELLE',
        'terms': 'Zelle only. Fast release within 10 minutes.',
        'status': 'ACTIVE',
        'createdAt': _hoursAgo(2),
        'activeHoursStart': '08:00',
        'activeHoursEnd': '22:00',
        'maxPaymentWindow': 15,
      },
      {
        'id': 2,
        'type': 'SELL',
        'crypto': 'USDT',
        'pricePerUSD': 15.50,
        'margin': 3.3,
        'minLimit': 100,
        'maxLimit': 1000,
        'paymentMethod': 'US_BANK_TRANSFER',
        'terms': 'US bank transfer only. Chase, BofA, Wells Fargo.',
        'status': 'ACTIVE',
        'createdAt': _hoursAgo(5),
        'activeHoursStart': '09:00',
        'activeHoursEnd': '21:00',
        'maxPaymentWindow': 20,
      },
      {
        'id': 3,
        'type': 'BUY',
        'crypto': 'USDT',
        'pricePerUSD': 15.35,
        'margin': 1.9,
        'minLimit': 30,
        'maxLimit': 300,
        'paymentMethod': 'VENMO',
        'terms': 'Venmo only. No third-party payments.',
        'status': 'PAUSED',
        'createdAt': _daysAgo(1),
        'activeHoursStart': '08:00',
        'activeHoursEnd': '20:00',
        'maxPaymentWindow': 15,
      },
    ],
  };

  // ── /stories/feed ───────────────────────────────────────────────────
  static Map<String, dynamic> storiesFeed() => {
    'groups': [
      {
        'authorId': 2,
        'author': {
          'username': 'Bella',
          'profilePictureUrl': 'https://i.pravatar.cc/150?img=12',
        },
        'hasUnseen': true,
        'isBoosted': false,
        'stories': [
          {
            'id': 's-1',
            'mediaUrl': 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400',
            'mediaType': 'IMAGE',
            'caption': 'Friday vibes at the spot',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(3),
          },
          {
            'id': 's-1b',
            'mediaUrl': 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=400',
            'mediaType': 'IMAGE',
            'caption': 'Dinner was unreal',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(2),
          },
        ],
      },
      {
        'authorId': 3,
        'author': {
          'username': 'Lamar',
          'profilePictureUrl': 'https://i.pravatar.cc/150?img=15',
        },
        'hasUnseen': true,
        'isBoosted': false,
        'stories': [
          {
            'id': 's-2',
            'mediaUrl': 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=400',
            'mediaType': 'IMAGE',
            'caption': 'New office setup',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(8),
          },
          {
            'id': 's-2b',
            'mediaUrl': 'https://images.unsplash.com/photo-1497366216548-37526070297c?w=400',
            'mediaType': 'IMAGE',
            'caption': 'Late night grind',
            'durationSeconds': 5,
            'boosted': false,
            'seen': false,
            'createdAt': _hoursAgo(6),
          },
        ],
      },
      {
        'authorId': 10,
        'author': {
          'username': 'crypto_gh',
          'profilePictureUrl': 'https://i.pravatar.cc/150?img=47',
        },
        'hasUnseen': false,
        'isBoosted': true,
        'stories': [
          {
            'id': 's-3',
            'mediaUrl': 'https://images.unsplash.com/photo-1639762681485-074b7f938ba0?w=400',
            'mediaType': 'IMAGE',
            'caption': 'New rates just dropped!',
            'durationSeconds': 5,
            'boosted': true,
            'seen': true,
            'createdAt': _hoursAgo(20),
          },
          {
            'id': 's-3b',
            'mediaUrl': 'https://images.unsplash.com/photo-1640340434855-6084b1f4901c?w=400',
            'mediaType': 'IMAGE',
            'caption': 'USDC pairs now live',
            'durationSeconds': 5,
            'boosted': false,
            'seen': true,
            'createdAt': _hoursAgo(5),
          },
        ],
      },
    ],
  };

  // ── /storefront/discover ─────────────────────────────────────────────
  static Map<String, dynamic> storefrontDiscover() => {
    'data': [
      {
        'id': 'biz-1',
        'name': "Chef Abby's",
        'logoUrl': null,
        'accentColor': '#F59E0B',
        'verified': true,
        'rating': 4.8,
        'followerCount': 1200,
        'isFollowing': false,
        'category': 'FOOD',
      },
      {
        'id': 'biz-2',
        'name': 'Advenr',
        'logoUrl': null,
        'accentColor': '#4F8EF7',
        'verified': true,
        'rating': 4.6,
        'followerCount': 850,
        'isFollowing': true,
        'category': 'FOOD',
      },
      {
        'id': 'biz-3',
        'name': 'Mr. Price',
        'logoUrl': null,
        'accentColor': '#00D97E',
        'verified': false,
        'rating': 4.3,
        'followerCount': 340,
        'isFollowing': false,
        'category': 'RETAIL',
      },
    ],
  };

  // ── /azm-stake/tier ──────────────────────────────────────────────────
  static Map<String, dynamic> stakingTier() => {
    'data': {
      'tier': 'GOLD',
      'apy': 12.5,
      'minimumStake': 1000.00,
      'currentStake': 5000.00,
      'rewardsEarned': 1860.00,
    },
  };

  // ── /azm-stake/stakes ────────────────────────────────────────────────
  static Map<String, dynamic> stakes() => {
    'data': [
      {
        'id': 'st-1',
        'amount': 5000.00,
        'tier': 'GOLD',
        'apy': 12.5,
        'startDate': _daysFromNow(-30),
        'endDate': _daysFromNow(335),
        'rewardsEarned': 1860.00,
        'status': 'ACTIVE',
      },
    ],
  };

  // ── /azm-auction/current ─────────────────────────────────────────────
  static Map<String, dynamic> auctionCurrent() => {
    'data': {
      'id': 'auc-1',
      'title': 'Rare Gold Skin NFT',
      'description': 'Limited edition gold card skin',
      'currentBid': 250.00,
      'bidders': 12,
      'endsAt': _daysFromNow(2),
      'image': null,
    },
  };

  // ── /azm/spend/history ───────────────────────────────────────────────
  static Map<String, dynamic> spendHistory() => {
    'data': [
      {'id': 'sp-1', 'category': 'Airtime', 'amount': 20.00, 'date': _hoursAgo(48)},
      {'id': 'sp-2', 'category': 'Data Bundle', 'amount': 35.00, 'date': _hoursAgo(96)},
    ],
  };

  // ── /trade-accounts/supported-methods ───────────────────────────────
  static Map<String, dynamic> supportedMethods() => {
    'data': [
      {'id': 'MTN_MOMO', 'label': 'MTN Mobile Money'},
      {'id': 'TELEKEL_CASH', 'label': 'Telecel Cash'},
      {'id': 'VODAFONE_CASH', 'label': 'Vodafone Cash'},
      {'id': 'BANK_TRANSFER', 'label': 'Bank Transfer'},
    ],
  };

  // ── /kyc/status ──────────────────────────────────────────────────────
  static Map<String, dynamic> kycStatus() => {'data': {'status': 'VERIFIED'}};

  // ── /users/profile ───────────────────────────────────────────────────
  static Map<String, dynamic> userProfile() => {
    'data': {
      'id': 1,
      'username': demoUsername,
      'email': 'pyrax@demo.azaman.app',
      'role': 'USER',
      'profilePictureUrl': 'https://i.pravatar.cc/150?img=8',
      'azamanId': 'AZM-000123456',
      'kycStatus': 'VERIFIED',
    },
  };

  // ── /users/me/milestones ────────────────────────────────────────────
  static Map<String, dynamic> milestones() => {
    'data': [
      {'id': 'ms-1', 'title': 'First Trade', 'completed': true, 'date': _daysFromNow(-60)},
      {'id': 'ms-2', 'title': 'First Deposit', 'completed': true, 'date': _daysFromNow(-90)},
      {'id': 'ms-3', 'title': '7-Day Login Streak', 'completed': true, 'date': _hoursAgo(1)},
      {'id': 'ms-4', 'title': 'First Susu Cycle', 'completed': false, 'date': null},
    ],
  };

  // ── /vaults/yield/strategies ────────────────────────────────────────
  static Map<String, dynamic> yieldStrategies() => {
    'data': [
      {'id': 'conservative', 'name': 'Conservative', 'apy': 5.5, 'risk': 'LOW'},
      {'id': 'balanced', 'name': 'Balanced', 'apy': 8.5, 'risk': 'MEDIUM'},
      {'id': 'aggressive', 'name': 'Aggressive', 'apy': 12.0, 'risk': 'HIGH'},
    ],
  };

  // ── /round-up ────────────────────────────────────────────────────────
  static Map<String, dynamic> roundUp() => {'data': {'enabled': true, 'totalSaved': 42.50}};

  // ── /wallet/deposit-address/polygon ─────────────────────────────────
  static Map<String, dynamic> depositAddress() => {
    'data': {'address': '0xDemo1234567890abcdef1234567890abcdef1234'}
  };

  // ── Empty/generic responses ──────────────────────────────────────────
  static Map<String, dynamic> emptyData() => {'data': []};
  static Map<String, dynamic> nullData() => {'data': null};
  static Map<String, dynamic> okSuccess() => {'data': {'ok': true}};

  // ── Helper: timestamps ───────────────────────────────────────────────
  static String _hoursAgo(int hours, [int addMinutes = 0]) {
    final now = DateTime.now();
    final t = now.subtract(Duration(hours: hours, minutes: addMinutes));
    return t.toUtc().toIso8601String();
  }

  static String _minutesAgo(int minutes) {
    final t = DateTime.now().subtract(Duration(minutes: minutes));
    return t.toUtc().toIso8601String();
  }

  static String _daysAgo(int days) {
    final t = DateTime.now().subtract(Duration(days: days));
    return t.toUtc().toIso8601String();
  }

  static String _daysFromNow(int days) {
    final t = DateTime.now().add(Duration(days: days));
    return t.toUtc().toIso8601String();
  }
}

// =============================================================================
// AZAMAN — Universal Search Overlay
//
// A Revolut/Linear-style universal search that searches across:
//   • Screens (quick navigation)
//   • Marketplace businesses
//   • Transactions
//   • People (friends/contacts)
//   • Susu groups
//   • Vaults
//
// Reference: Linear (command palette search), Revolut (universal search),
//            Telegram (search across everything), Notion (quick find)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

// ── Search result model ──────────────────────────────────────────────────────

enum SearchCategory {
  actions('Actions', HugeIconsSolid.search01, Color(0xFF3B97F7)),
  businesses('Businesses', HugeIconsSolid.store01, Color(0xFF10B981)),
  people('People', HugeIconsSolid.userGroup, Color(0xFF9C59FF)),
  money('Money', HugeIconsSolid.moneyReceiveFlow01, Color(0xFFFFD700)),
  groups('Groups', HugeIconsSolid.group01, Color(0xFFF59E0B)),
  vaults('Vaults', HugeIconsSolid.safeBox, Color(0xFF6366F1)),
  pages('Pages', HugeIconsSolid.dashboardSquare01, Color(0xFF64748B));

  final String label;
  final IconData icon;
  final Color color;
  const SearchCategory(this.label, this.icon, this.color);
}

class SearchResult {
  final String id;
  final String title;
  final String? subtitle;
  final SearchCategory category;
  final IconData icon;
  final VoidCallback? onTap;

  const SearchResult({
    required this.id,
    required this.title,
    this.subtitle,
    required this.category,
    required this.icon,
    this.onTap,
  });
}

// ── Quick actions (always available) ────────────────────────────────────────

class _QuickAction {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final List<String> keywords;

  _QuickAction({
    required this.title,
    this.subtitle = '',
    required this.icon,
    required this.route,
    this.keywords = const [],
  });
}

final _quickActions = <_QuickAction>[
  _QuickAction(title: 'Send Money', icon: HugeIconsSolid.moneySend01, route: '/deposit', keywords: ['send', 'transfer', 'pay']),
  _QuickAction(title: 'Withdraw', icon: HugeIconsSolid.moneySendSquare, route: '/withdraw', keywords: ['withdraw', 'cash out']),
  _QuickAction(title: 'New Trade', icon: HugeIconsSolid.exchange01, route: '/trade/create', keywords: ['trade', 'exchange', 'buy', 'sell', 'crypto']),
  _QuickAction(title: 'Marketplace', icon: HugeIconsSolid.store01, route: '/marketplace', keywords: ['market', 'shop', 'business', 'store']),
  _QuickAction(title: 'Susu Groups', icon: HugeIconsSolid.group01, route: '/susu', keywords: ['susu', 'savings', 'group', 'rosca']),
  _QuickAction(title: 'Vaults', icon: HugeIconsSolid.safeBox, route: '/savings', keywords: ['vault', 'savings', 'goal', 'save']),
  _QuickAction(title: 'Chat', icon: HugeIconsSolid.message01, route: '/messages', keywords: ['chat', 'message', 'talk', 'dm']),
  _QuickAction(title: 'Notifications', icon: HugeIconsSolid.notification01, route: '/notifications', keywords: ['notification', 'alert', 'bell']),
  _QuickAction(title: 'Profile', icon: HugeIconsSolid.userCircle, route: '/profile', keywords: ['profile', 'settings', 'account']),
  _QuickAction(title: 'Referrals', icon: HugeIconsSolid.gift, route: '/referral', keywords: ['refer', 'invite', 'friend', 'reward']),
  _QuickAction(title: 'QR Scanner', icon: HugeIconsSolid.qrCode01, route: '/qr-scanner', keywords: ['qr', 'scan', 'code']),
  _QuickAction(title: 'Transaction History', icon: HugeIconsSolid.note01, route: '/transactions', keywords: ['transaction', 'history', 'statement']),
  _QuickAction(title: 'Spending Insights', icon: HugeIconsSolid.dashboardSquare01, route: '/spending-insights', keywords: ['spending', 'budget', 'insights', 'analytics', 'budget']),
];

// ── Universal Search Screen ─────────────────────────────────────────────────

class UniversalSearchScreen extends ConsumerStatefulWidget {
  const UniversalSearchScreen({super.key});

  @override
  ConsumerState<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends ConsumerState<UniversalSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  List<SearchResult> _results = [];

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }

    final results = <SearchResult>[];

    // Search quick actions / pages
    for (final action in _quickActions) {
      final titleMatch = action.title.toLowerCase().contains(q);
      final keywordMatch = action.keywords.any((k) => k.contains(q));
      if (titleMatch || keywordMatch) {
        results.add(SearchResult(
          id: 'action_${action.title}',
          title: action.title,
          subtitle: action.subtitle,
          category: SearchCategory.pages,
          icon: action.icon,
          onTap: () {
            AzamanHaptics.nav();
            context.push(action.route);
            Navigator.of(context).pop();
          },
        ));
      }
    }

    // TODO: When backend search endpoint is available, add network results
    // for businesses, people, transactions, susu groups, vaults

    setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.black54,
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 60),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── Search header ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
                child: Row(
                  children: [
                    Icon(HugeIconsSolid.search01, size: 20, color: colors.textTertiary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        style: TextStyle(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'Search anything...',
                          hintStyle: TextStyle(color: colors.textTertiary, fontSize: 16),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        textInputAction: TextInputAction.search,
                        onChanged: (value) {
                          _query = value;
                          _performSearch(value);
                        },
                        onSubmitted: _performSearch,
                      ),
                    ),
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          AzamanHaptics.nav();
                          _searchController.clear();
                          setState(() {
                            _query = '';
                            _results = [];
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colors.softSurface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(HugeIconsSolid.cancel01, size: 16, color: colors.textTertiary),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: colors.textTertiary, fontSize: 16),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Divider(height: 1, color: colors.border),

              // ── Results ─────────────────────────────────────────────────────
              Expanded(
                child: _query.isEmpty
                    ? _buildQuickActions(colors)
                    : _results.isEmpty
                        ? _buildEmptyState(colors)
                        : _buildResults(colors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(AzamanColors colors) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _quickActions.length,
      itemBuilder: (context, index) {
        final action = _quickActions[index];
        return _SearchTile(
          icon: action.icon,
          iconColor: SearchCategory.pages.color,
          title: action.title,
          subtitle: action.subtitle,
          colors: colors,
          onTap: () {
            AzamanHaptics.nav();
            context.push(action.route);
            Navigator.of(context).pop();
          },
        ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.05, end: 0);
      },
    );
  }

  Widget _buildEmptyState(AzamanColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(HugeIconsSolid.search01, size: 48, color: colors.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No results for "$_query"',
            style: TextStyle(color: colors.textTertiary, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching for actions, pages, or features',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(AzamanColors colors) {
    // Group results by category
    final grouped = <SearchCategory, List<SearchResult>>{};
    for (final r in _results) {
      grouped.putIfAbsent(r.category, () => []).add(r);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: grouped.length,
      itemBuilder: (context, groupIndex) {
        final category = grouped.keys.elementAt(groupIndex);
        final items = grouped[category]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
              child: Text(
                category.label,
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ...items.map((r) => _SearchTile(
                  icon: r.icon,
                  iconColor: r.category.color,
                  title: r.title,
                  subtitle: r.subtitle,
                  colors: colors,
                  onTap: r.onTap ?? () {},
                )),
          ],
        );
      },
    );
  }
}

// ── Search tile ──────────────────────────────────────────────────────────────

class _SearchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final AzamanColors colors;
  final VoidCallback onTap;

  const _SearchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(color: colors.textTertiary, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(HugeIconsSolid.arrowRight01, size: 16, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

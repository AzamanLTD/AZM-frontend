// =============================================================================
// CHAT PROFILE SCREEN — Phase UI-5 (2026-05-26)
//
// Reachable by tapping a user's avatar inside any chat surface (currently
// wired from `friend_chat_screen.dart`). Two-tier layout:
//
//   • IDENTITY TIER (top half)
//       - Friend avatar + username + KYC badge
//       - "Friends since" timestamp + mutual trade count
//       - Inline-editable LOCAL NICKNAME (per-friendship override)
//
//   • MEDIA & LEDGER VAULT (bottom half)
//       - Tabs: Media | Docs & Links | Tickets | Receipts
//       - Media         — chronological grid of images + videos
//       - Docs & Links  — scrollable list of documents + link previews
//       - Tickets       — list of all open/closed/cancelled tickets between
//                         the two friends (reuses Phase UI-4 dashboard data)
//       - Receipts      — immutable P2P transfer records with PDF download
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:azaman/config.dart';
import 'package:azaman/providers/chat_profile_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/ticket_provider.dart';
import 'package:azaman/screens/tickets/ticket_workspace_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/chat_profile_service.dart';
import 'package:azaman/services/ticket_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/trust_breakdown_sheet.dart';
import 'package:hugeicons_pro/hugeicons.dart';

class ChatProfileScreen extends ConsumerStatefulWidget {
  final String friendshipId;
  final String fallbackUsername;
  const ChatProfileScreen({
    super.key,
    required this.friendshipId,
    required this.fallbackUsername,
  });

  @override
  ConsumerState<ChatProfileScreen> createState() => _ChatProfileScreenState();
}

class _ChatProfileScreenState extends ConsumerState<ChatProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(chatProfileProvider(widget.friendshipId).notifier).primeAll();
      ref
          .read(ticketDashboardProvider(widget.friendshipId).notifier)
          .refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(chatProfileProvider(widget.friendshipId));
    final profile = state.profile;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          'Chat Profile',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: state.profileLoading && profile == null
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : (profile == null
              ? _ErrorRetry(
                  error: state.error ?? 'Could not load profile.',
                  onRetry: () => ref
                      .read(chatProfileProvider(widget.friendshipId).notifier)
                      .primeAll(),
                  colors: colors,
                )
              : Column(
                  children: [
                    _IdentityTier(
                      profile: profile,
                      fallbackUsername: widget.fallbackUsername,
                      colors: colors,
                      onEditNickname: () => _editNickname(profile),
                      onShowTrustBreakdown: () => _showTrustBreakdown(profile),
                    ),
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.center,
                        indicator: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor:
                            colors.isDark ? Colors.black : Colors.white,
                        unselectedLabelColor: colors.textSecondary,
                        labelStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        dividerColor: Colors.transparent,
                        splashFactory: NoSplash.splashFactory,
                        overlayColor:
                            WidgetStateProperty.all(Colors.transparent),
                        onTap: (_) => AzamanHaptics.toggle(),
                        tabs: [
                          const Tab(height: 32, text: 'Media'),
                          const Tab(height: 32, text: 'Docs & Links'),
                          // Phase UI-POLISH (2026-05-26): show counts
                          // on Tickets + Receipts tabs so users can
                          // see how much history exists in each at a
                          // glance.
                          _CountedTab(
                            label: 'Tickets',
                            count: ref
                                    .watch(ticketDashboardProvider(
                                        widget.friendshipId))
                                    .openTickets
                                    .length +
                                ref
                                    .watch(ticketDashboardProvider(
                                        widget.friendshipId))
                                    .closedTickets
                                    .length +
                                ref
                                    .watch(ticketDashboardProvider(
                                        widget.friendshipId))
                                    .cancelledTickets
                                    .length,
                          ),
                          _CountedTab(
                            label: 'Receipts',
                            count: state.receiptItems.length,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _MediaTab(
                            friendshipId: widget.friendshipId,
                          ),
                          _DocsLinksTab(
                            friendshipId: widget.friendshipId,
                          ),
                          _TicketsTab(
                            friendshipId: widget.friendshipId,
                            friendUsername: profile.friend.username,
                          ),
                          _ReceiptsTab(
                            friendshipId: widget.friendshipId,
                          ),
                        ],
                      ),
                    ),
                  ],
                )),
    );
  }

  Future<void> _editNickname(ChatProfileResponse profile) async {
    final colors = ref.read(themeProvider).colors;
    final controller =
        TextEditingController(text: profile.myNicknameForFriend ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Set nickname',
            style: TextStyle(color: colors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A custom nickname for ${profile.friend.username}, visible only to you. Leave blank to clear.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 40,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. "Mom" / "Trade buddy"',
                hintStyle:
                    TextStyle(color: colors.textTertiary, fontSize: 13),
                filled: true,
                fillColor: colors.card,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colors.accent, width: 1.2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel',
                style: TextStyle(color: colors.textTertiary)),
          ),
          if (profile.myNicknameForFriend != null &&
              profile.myNicknameForFriend!.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__CLEAR__'),
              child: Text('Clear',
                  style: TextStyle(color: colors.danger)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Save',
                style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (result == null) return; // user cancelled
    AzamanHaptics.confirm();
    final value = result == '__CLEAR__' ? null : result;
    await ref
        .read(chatProfileProvider(widget.friendshipId).notifier)
        .setNickname(value);
  }

  // Phase UI-7 (2026-05-27): tap-popup with the per-category trust
  // breakdown. Same widget the chat AppBar opens, but driven from the
  // already-loaded profile data so it's instant (no extra round-trip).
  void _showTrustBreakdown(ChatProfileResponse profile) {
    AzamanHaptics.toggle();
    final f = profile.friend;
    showTrustBreakdownSheet(
      context,
      username: f.username,
      breakdown: f.completedTransactionsBreakdown ??
          TrustBreakdown(
            // Defensive fallback — older BE without the breakdown field
            // still gets a sensible split: every completed P2P trade we
            // know of, no transfer / ticket data so they read 0.
            tradesCompleted: f.tradesCompleted,
            completedTransfers: 0,
            closedTickets: 0,
          ),
      rating: f.rating,
      positiveReviews: f.positiveReviews,
      negativeReviews: f.negativeReviews,
      isVerifiedVendor: f.isVerifiedVendor,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IDENTITY TIER
// ─────────────────────────────────────────────────────────────────────────────
class _IdentityTier extends StatelessWidget {
  final ChatProfileResponse profile;
  final String fallbackUsername;
  final AzamanColors colors;
  final VoidCallback onEditNickname;
  final VoidCallback onShowTrustBreakdown;
  const _IdentityTier({
    required this.profile,
    required this.fallbackUsername,
    required this.colors,
    required this.onEditNickname,
    required this.onShowTrustBreakdown,
  });

  @override
  Widget build(BuildContext context) {
    final username =
        profile.friend.username.isNotEmpty ? profile.friend.username : fallbackUsername;
    final nickname = profile.myNicknameForFriend;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent.withOpacity(0.15),
                  border:
                      Border.all(color: colors.accent.withOpacity(0.4), width: 1),
                ),
                child: Center(
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nickname?.isNotEmpty == true ? nickname! : username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        // Phase UI-7: prefer the verified VENDOR badge
                        // (theme accent) when applicable; fall back to
                        // the green KYC tick for normal users with
                        // VERIFIED status. Vendor flag is stricter so
                        // we check it first.
                        if (profile.friend.isVerifiedVendor)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Tooltip(
                              message: 'Verified vendor',
                              child: Icon(HugeIconsSolid.checkmarkCircle01,
                                  color: colors.accent, size: 18),
                            ),
                          )
                        else if (profile.friend.kycStatus == 'VERIFIED')
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(HugeIconsSolid.checkmarkCircle01,
                                color: const Color(0xFF22C55E), size: 18),
                          ),
                      ],
                    ),
                    if (nickname?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '@$username',
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Friends since ${_formatDate(profile.friendSince)}',
                      style: TextStyle(
                          color: colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEditNickname,
                icon: Icon(HugeIconsSolid.pencilEdit01,
                    color: colors.accent, size: 20),
                tooltip: 'Edit nickname',
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Phase UI-7 (2026-05-27): the stat row now leads with the
          // GLOBAL completed-transactions count (tappable → breakdown
          // sheet), the friend's rating, and the mutual-trades number
          // for relationship context. The previous "Their trades" pill
          // showed only User.tradesCompleted (P2P only) and was
          // misleading next to the chat header which shows the global
          // count. The two now agree.
          Row(
            children: [
              Expanded(
                child: _StatPill(
                  icon: HugeIconsSolid.task01,
                  label: 'Completed',
                  value: '${profile.friend.completedTransactions}',
                  colors: colors,
                  onTap: onShowTrustBreakdown,
                  highlight: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatPill(
                  icon: HugeIconsSolid.star,
                  label: 'Rating',
                  value: profile.friend.rating != null
                      ? profile.friend.rating!.toStringAsFixed(1)
                      : '—',
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatPill(
                  icon: HugeIconsSolid.agreement01,
                  label: 'Mutual',
                  value: '${profile.mutualTradesCompleted}',
                  colors: colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AzamanColors colors;
  final VoidCallback? onTap;
  final bool highlight;
  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = highlight ? colors.accent : colors.textTertiary;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? colors.accent.withOpacity(0.06)
            : colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? colors.accent.withOpacity(0.30)
              : colors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 12),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4),
                ),
              ),
              if (onTap != null)
                Icon(
                  HugeIconsSolid.arrowRight01,
                  color: iconColor,
                  size: 14,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEDIA TAB (Images + Videos)
// ─────────────────────────────────────────────────────────────────────────────
class _MediaTab extends ConsumerWidget {
  final String friendshipId;
  const _MediaTab({required this.friendshipId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatProfileProvider(friendshipId));
    final colors = ref.watch(themeProvider).colors;
    final notifier = ref.read(chatProfileProvider(friendshipId).notifier);

    if (state.mediaLoading && state.mediaItems.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (state.mediaItems.isEmpty) {
      return _EmptyVault(
        icon: HugeIconsSolid.image01,
        label: 'No shared media yet.',
        colors: colors,
        onRefresh: notifier.refreshMedia,
      );
    }
    return RefreshIndicator(
      onRefresh: notifier.refreshMedia,
      color: colors.accent,
      backgroundColor: colors.card,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemCount: state.mediaItems.length,
        itemBuilder: (_, i) =>
            _MediaTile(item: state.mediaItems[i], colors: colors),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final VaultItem item;
  final AzamanColors colors;
  const _MediaTile({required this.item, required this.colors});

  String _resolve(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final apiBase = AppConfig.apiUrl;
    final origin = apiBase.endsWith('/api')
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;
    return '$origin$url';
  }

  @override
  Widget build(BuildContext context) {
    final url = item.mediaUrl;
    return GestureDetector(
      onTap: () async {
        if (url == null) return;
        HapticFeedback.lightImpact();
        await launchUrl(Uri.parse(_resolve(url)),
            mode: LaunchMode.externalApplication);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.type == 'IMAGE' && url != null)
              Image.network(
                _resolve(url),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: colors.card,
                  alignment: Alignment.center,
                  child: Icon(HugeIconsSolid.image01,
                      color: colors.textTertiary, size: 22),
                ),
              )
            else
              Container(
                color: colors.card,
                alignment: Alignment.center,
                child: Icon(
                  item.type == 'VIDEO'
                      ? HugeIconsSolid.play
                      : HugeIconsSolid.image01,
                  color: colors.textTertiary,
                  size: 28,
                ),
              ),
            if (item.type == 'VIDEO')
              Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(HugeIconsSolid.play,
                      color: Colors.white, size: 18),
                ),
              ),
            if (item.source == 'TICKET')
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.accent.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'TICKET',
                    style: TextStyle(
                      color: colors.isDark ? Colors.black : Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCS & LINKS TAB
// ─────────────────────────────────────────────────────────────────────────────
class _DocsLinksTab extends ConsumerWidget {
  final String friendshipId;
  const _DocsLinksTab({required this.friendshipId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatProfileProvider(friendshipId));
    final colors = ref.watch(themeProvider).colors;
    final notifier = ref.read(chatProfileProvider(friendshipId).notifier);

    if (state.docsLoading && state.docsLinkItems.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (state.docsLinkItems.isEmpty) {
      return _EmptyVault(
        icon: HugeIconsSolid.link01,
        label: 'No shared documents or links yet.',
        colors: colors,
        onRefresh: notifier.refreshDocsLinks,
      );
    }
    return RefreshIndicator(
      onRefresh: notifier.refreshDocsLinks,
      color: colors.accent,
      backgroundColor: colors.card,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: state.docsLinkItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) =>
            _DocLinkRow(item: state.docsLinkItems[i], colors: colors),
      ),
    );
  }
}

class _DocLinkRow extends StatelessWidget {
  final VaultItem item;
  final AzamanColors colors;
  const _DocLinkRow({required this.item, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (item.type == 'LINK') {
      final preview = item.linkPreview ?? const {};
      final title = preview['title']?.toString() ?? item.content ?? 'Link';
      final siteName = preview['siteName']?.toString();
      final url = item.content ?? '';
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          if (url.isEmpty) return;
          HapticFeedback.lightImpact();
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Icon(HugeIconsSolid.link01, color: colors.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                    if (siteName != null && siteName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          siteName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.textTertiary, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(HugeIconsSolid.share01,
                  color: colors.textTertiary, size: 16),
            ],
          ),
        ),
      );
    }

    // DOCUMENT
    final filename = item.mediaUrl?.split('/').last ?? 'Document';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openDocument(context, item, colors),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_iconForMime(item.mediaMimeType),
                  color: colors.warning, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                  if (item.mediaSize != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _formatBytes(item.mediaSize!),
                        style: TextStyle(
                            color: colors.textTertiary, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            Icon(HugeIconsSolid.download01,
                color: colors.textTertiary, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _openDocument(
      BuildContext context, VaultItem item, AzamanColors colors) async {
    final url = item.mediaUrl;
    if (url == null) return;
    final apiBase = AppConfig.apiUrl;
    final origin = apiBase.endsWith('/api')
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;
    final resolved =
        url.startsWith('http') ? url : '$origin$url';
    try {
      final res = await http.get(Uri.parse(resolved));
      if (res.statusCode != 200) {
        throw Exception('Download failed: ${res.statusCode}');
      }
      final dir = await getTemporaryDirectory();
      final filename = url.split('/').last;
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(res.bodyBytes);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $e')),
        );
      }
    }
  }

  IconData _iconForMime(String? mime) {
    if (mime == null) return HugeIconsSolid.file01;
    if (mime.contains('pdf')) return HugeIconsSolid.pdf01;
    if (mime.contains('word') || mime.contains('msword')) {
      return HugeIconsSolid.note01;
    }
    if (mime.contains('excel') || mime.contains('spreadsheet')) {
      return HugeIconsSolid.grid02;
    }
    if (mime.contains('presentation')) return HugeIconsSolid.film01;
    if (mime.startsWith('text')) return HugeIconsSolid.note01;
    return HugeIconsSolid.file01;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TICKETS TAB (reuses ticketDashboardProvider from Phase UI-4)
// ─────────────────────────────────────────────────────────────────────────────
class _TicketsTab extends ConsumerWidget {
  final String friendshipId;
  final String friendUsername;
  const _TicketsTab({
    required this.friendshipId,
    required this.friendUsername,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final state = ref.watch(ticketDashboardProvider(friendshipId));
    final notifier = ref.read(ticketDashboardProvider(friendshipId).notifier);

    final all = <Ticket>[
      ...state.openTickets,
      ...state.closedTickets,
      ...state.cancelledTickets,
    ]..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));

    if (state.isLoading && all.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (all.isEmpty) {
      return _EmptyVault(
        icon: HugeIconsSolid.ticket01,
        label: 'No tickets between you yet.',
        colors: colors,
        onRefresh: notifier.refresh,
      );
    }
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      color: colors.accent,
      backgroundColor: colors.card,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final t = all[i];
          return _TicketRow(ticket: t, colors: colors, friendUsername: friendUsername);
        },
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  final Ticket ticket;
  final String friendUsername;
  final AzamanColors colors;
  const _TicketRow({
    required this.ticket,
    required this.friendUsername,
    required this.colors,
  });

  Color get _statusColor {
    switch (ticket.status) {
      case TicketStatus.open: return colors.success;
      case TicketStatus.closed: return colors.textTertiary;
      case TicketStatus.cancelled: return colors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TicketWorkspaceScreen(
            ticketId: ticket.id,
            friendUsername: friendUsername,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(HugeIconsSolid.ticket01,
                  color: colors.accent, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ticket.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          ticket.status.label.toUpperCase(),
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${ticket.type.label} · ${ticket.targetAmount.toStringAsFixed(2)} ${ticket.targetCurrency}',
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(HugeIconsSolid.arrowRight01,
                color: colors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECEIPTS TAB (immutable P2P transfer history with PDF download)
// ─────────────────────────────────────────────────────────────────────────────
class _ReceiptsTab extends ConsumerStatefulWidget {
  final String friendshipId;
  const _ReceiptsTab({required this.friendshipId});

  @override
  ConsumerState<_ReceiptsTab> createState() => _ReceiptsTabState();
}

class _ReceiptsTabState extends ConsumerState<_ReceiptsTab> {
  final Set<String> _downloading = {};

  Future<void> _downloadReceipt(ReceiptItem r) async {
    final colors = ref.read(themeProvider).colors;
    if (r.downloadUrl == null) return;
    setState(() => _downloading.add(r.id));
    try {
      final res = await apiClient.get(r.downloadUrl!);
      if (res.statusCode != 200) {
        throw Exception('Server returned ${res.statusCode}');
      }
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/azaman-transfer-receipt-${r.id.substring(0, r.id.length < 8 ? r.id.length : 8)}.pdf');
      await file.writeAsBytes(res.bodyBytes);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: colors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProfileProvider(widget.friendshipId));
    final colors = ref.watch(themeProvider).colors;
    final notifier =
        ref.read(chatProfileProvider(widget.friendshipId).notifier);

    if (state.receiptsLoading && state.receiptItems.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (state.receiptItems.isEmpty) {
      return _EmptyVault(
        icon: HugeIconsSolid.receiptDollar,
        label: 'No P2P transfers between you yet.',
        sublabel: 'Casual money transfers (with a tracking reason) appear here as immutable receipts.',
        colors: colors,
        onRefresh: notifier.refreshReceipts,
      );
    }
    return RefreshIndicator(
      onRefresh: notifier.refreshReceipts,
      color: colors.accent,
      backgroundColor: colors.card,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        // +1 for the optional "Load more" footer when more pages exist.
        itemCount:
            state.receiptItems.length + (state.receiptsHasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i >= state.receiptItems.length) {
            return _LoadMoreButton(
              isLoading: state.receiptsLoadingMore,
              colors: colors,
              onTap: notifier.loadMoreReceipts,
            );
          }
          final r = state.receiptItems[i];
          return _ReceiptRow(
            receipt: r,
            colors: colors,
            isDownloading: _downloading.contains(r.id),
            onDownload: () => _downloadReceipt(r),
          );
        },
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final ReceiptItem receipt;
  final AzamanColors colors;
  final bool isDownloading;
  final VoidCallback onDownload;
  const _ReceiptRow({
    required this.receipt,
    required this.colors,
    required this.isDownloading,
    required this.onDownload,
  });

  Color get _statusColor {
    switch (receipt.status) {
      case 'COMPLETED': return colors.success;
      case 'PENDING':   return colors.warning;
      case 'DECLINED':  return colors.danger;
      case 'FAILED':    return colors.danger;
      case 'INSUFFICIENT_FUNDS': return colors.danger;
      default:          return colors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSent = receipt.direction == 'SENT';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isSent ? colors.warning : colors.success).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isSent ? HugeIconsSolid.arrowUp01 : HugeIconsSolid.arrowDown01,
              color: isSent ? colors.warning : colors.success,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${isSent ? "Sent" : "Received"} ${receipt.amount.toStringAsFixed(2)} ${receipt.currency}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        receipt.status,
                        style: TextStyle(
                          color: _statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (receipt.reference != null && receipt.reference!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      receipt.reference!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: colors.textSecondary, fontSize: 11),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    _relativeTime(receipt.createdAt),
                    style: TextStyle(color: colors.textTertiary, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          if (receipt.isCompleted && receipt.downloadUrl != null)
            IconButton(
              onPressed: isDownloading ? null : onDownload,
              icon: isDownloading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: colors.accent),
                    )
                  : Icon(HugeIconsSolid.download01,
                      color: colors.accent, size: 18),
              tooltip: 'Download receipt PDF',
            ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared empty / error placeholders
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyVault extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final AzamanColors colors;
  final Future<void> Function() onRefresh;
  const _EmptyVault({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onRefresh,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: colors.accent,
      backgroundColor: colors.card,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(40),
        children: [
          const SizedBox(height: 60),
          Icon(icon, color: colors.textTertiary, size: 44),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 6),
            Text(
              sublabel!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final AzamanColors colors;
  const _ErrorRetry({
    required this.error,
    required this.onRetry,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HugeIconsSolid.alertCircle,
                color: colors.danger, size: 36),
            const SizedBox(height: 10),
            Text('Could not load profile',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textTertiary, fontSize: 11)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.accent.withOpacity(0.4)),
              ),
              child: Text('Retry', style: TextStyle(color: colors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Custom tab widget that renders a label + a small count chip when count>0.
// Used by the Tickets and Receipts tabs in the vault.
// ─────────────────────────────────────────────────────────────────────────────
class _CountedTab extends StatelessWidget {
  final String label;
  final int count;
  const _CountedTab({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Load-more footer for the Receipts vault tab (Phase UI-POLISH).
// ─────────────────────────────────────────────────────────────────────────────
class _LoadMoreButton extends StatelessWidget {
  final bool isLoading;
  final AzamanColors colors;
  final VoidCallback onTap;
  const _LoadMoreButton({
    required this.isLoading,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton(
        onPressed: isLoading ? null : onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.accent.withOpacity(0.4)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        child: isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              )
            : Text(
                'Load more',
                style: TextStyle(
                  color: colors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
      ),
    );
  }
}

// =============================================================================
// AZAMAN — ACCOUNT ACTIVITY  (Phase F)
//
// Renders the user's security audit trail. Wired to:
//
//   GET /api/users/me/security-logs?page=N&limit=20
//   auth: Bearer token (protect middleware)
//
// Backend returns paginated entries from the Notification table where
// category='SECURITY_ACCOUNT', ordered DESC by createdAt. Phase F adds
// new entries to this stream automatically (e.g. password-change writes
// a SECURITY_ACCOUNT notification).
//
// UX: pull-to-refresh, infinite scroll, skeletonless empty/error states
// kept minimal for now — Phase H will swap to the proper skeleton_loader
// shimmer per the audit roadmap.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/skeleton_loader.dart';
import 'package:azaman/widgets/staggered_item.dart';
import 'package:azaman/widgets/az_pull_to_refresh.dart';


class AccountActivityScreen extends ConsumerStatefulWidget {
  const AccountActivityScreen({super.key});

  @override
  ConsumerState<AccountActivityScreen> createState() =>
      _AccountActivityScreenState();
}

class _AccountActivityScreenState
    extends ConsumerState<AccountActivityScreen> {
  static const int _pageSize = 20;

  final ScrollController _scroll = ScrollController();
  final List<_ActivityEntry> _entries = [];

  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Defer the first fetch to the next frame so the scaffold is mounted
    // before any setState calls fire.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _entries.clear();
      _page = 1;
      _hasMore = true;
      _error = null;
    });
    await _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    try {
      final response = await apiClient
          .get('/users/me/security-logs?page=$_page&limit=$_pageSize');
      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic> && data['success'] == true) {
        final List rawLogs = (data['logs'] as List?) ?? const [];
        final int total = (data['total'] as num?)?.toInt() ?? 0;

        final parsed = rawLogs
            .whereType<Map<String, dynamic>>()
            .map(_ActivityEntry.fromJson)
            .toList(growable: false);

        if (!mounted) return;
        setState(() {
          _entries.addAll(parsed);
          _hasMore = _entries.length < total && parsed.isNotEmpty;
          if (parsed.isNotEmpty) _page += 1;
          _error = null;
        });
      } else {
        setState(() => _error =
            (data is Map<String, dynamic>)
                ? (data['message']?.toString() ?? 'Could not load activity.')
                : 'Could not load activity.');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Account Activity',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: AzPullToRefresh(
        onRefresh: _loadInitial,
        child: _buildBody(colors),
      ),
    );
  }

  Widget _buildBody(AzamanColors colors) {
    if (_entries.isEmpty && _loading) {
      // Skeleton loading — matches existing transaction row layout
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              SkeletonBlock(height: 40, width: 40, borderRadius: BorderRadius.circular(20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBlock(height: 14, width: double.infinity, borderRadius: BorderRadius.circular(4)),
                    const SizedBox(height: 6),
                    SkeletonBlock(height: 12, width: 120, borderRadius: BorderRadius.circular(4)),
                  ],
                ),
              ),
              SkeletonBlock(height: 16, width: 60, borderRadius: BorderRadius.circular(4)),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty && _error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline,
              color: colors.danger, size: 48),
          const SizedBox(height: 12),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _loadInitial,
              child: Text('Retry',
                  style: TextStyle(color: colors.accent)),
            ),
          ),
        ],
      );
    }

    if (_entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.history,
              color: colors.textTertiary, size: 56),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'No activity yet',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Sign-ins, password changes, and security events show here.',
              style:
                  TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _entries.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _entries.length) {
          // Tail loader
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              ),
            ),
          );
        }
        return StaggeredItem(
          index: i,
          child: _entryCard(_entries[i], colors),
        );
      },
    );
  }

  Widget _entryCard(_ActivityEntry e, AzamanColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.accentSurface,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(
              _iconFor(e.title),
              color: colors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  e.body,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTimestamp(e.createdAt),
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String title) {
    final t = title.toLowerCase();
    if (t.contains('password')) return Icons.lock_outline;
    if (t.contains('2fa') || t.contains('two-factor')) {
      return Icons.security;
    }
    if (t.contains('pin')) return Icons.dialpad;
    if (t.contains('login') || t.contains('signed in')) {
      return Icons.login;
    }
    if (t.contains('logout')) return Icons.logout;
    if (t.contains('device')) return Icons.smartphone_outlined;
    return Icons.shield_outlined;
  }

  String _formatTimestamp(DateTime? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    // Date-style for older entries
    final yyyy = ts.year.toString().padLeft(4, '0');
    final mm = ts.month.toString().padLeft(2, '0');
    final dd = ts.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }
}

class _ActivityEntry {
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool isRead;

  const _ActivityEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
  });

  factory _ActivityEntry.fromJson(Map<String, dynamic> json) {
    DateTime? ts;
    final raw = json['createdAt']?.toString();
    if (raw != null && raw.isNotEmpty) {
      ts = DateTime.tryParse(raw);
    }
    return _ActivityEntry(
      id: json['id']?.toString() ?? '',
      title: (json['title']?.toString() ?? 'Account event'),
      body: (json['body']?.toString() ??
          json['message']?.toString() ??
          ''),
      createdAt: ts,
      isRead: json['isRead'] == true,
    );
  }
}

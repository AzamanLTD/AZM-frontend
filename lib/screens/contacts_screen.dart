import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../services/contact_service.dart';
import '../widgets/story_ring.dart';
import '../providers/theme_provider.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});
  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  List<RecentContact> _recent = [];
  List<MatchedContact> _matched = [];
  bool _loading = false;

  /// CONSENT BEFORE PERMISSION. False until the user reads the explanation
  /// and taps "Enable contacts"; the OS prompt is never the first thing they
  /// see, and refusing does not block anything else in the app.
  bool _consented = false;

  /// The honest outcome of the last discovery attempt. `null` means we never
  /// asked. An empty match list is only one of several possible states, and
  /// the copy for each says which one actually happened.
  ContactDiscoveryStatus? _status;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final recent = await ContactService.instance.getRecent();
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  Future<void> _findPeople() async {
    setState(() {
      _loading = true;
      _consented = true;
      _statusMessage = null;
    });
    final result = await ContactService.instance.discoverExistingMembers();
    if (!mounted) return;
    setState(() {
      _matched = result.matches;
      _status = result.status;
      _statusMessage = result.message;
      _loading = false;
    });
  }

  void _notNow() {
    setState(() {
      _consented = true;
      _status = ContactDiscoveryStatus.permissionDenied;
      _statusMessage = null;
    });
  }

  Future<void> _invite() async {
    final link = await ContactService.instance.getInviteLink();
    if (link.isNotEmpty) {
      await Share.share('Join me on Azaman: $link');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: colors.accent))
            : CustomScrollView(
                slivers: [
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    pinned: false,
                    floating: true,
                    title: Text(
                      'Contacts',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: _invite,
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_add_alt,
                              color: colors.accent,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Invite',
                              style: TextStyle(
                                color: colors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_recent.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 92,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _recent.length,
                          itemBuilder: (_, i) {
                            final c = _recent[i];
                            return Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: Column(
                                children: [
                                  StoryRing(
                                    avatarUrl: c.profilePictureUrl,
                                    counts: const StoryRingCounts.empty(),
                                    isBoosted: false,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      c.username,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  if (!_consented)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      sliver: SliverToBoxAdapter(child: _consentCard(colors)),
                    ),
                  if (_consented && !_loading)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      sliver: SliverToBoxAdapter(child: _discoveryNote(colors)),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'On Azaman',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((_, i) {
                      final m = _matched[i];
                      return ListTile(
                        leading: StoryRing(
                          avatarUrl: m.avatar,
                          counts: const StoryRingCounts.empty(),
                          isBoosted: false,
                          size: 46,
                        ),
                        title: Text(
                          m.displayName,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.chat_bubble_outline,
                            color: colors.accent,
                          ),
                          onPressed: () => _openChat(m),
                        ),
                      );
                    }, childCount: _matched.length),
                  ),
                ],
              ),
      ),
    );
  }

  void _openChat(MatchedContact m) {
    // Navigate to / create a friendship + push PersonalChatInterface,
    // reusing your existing friend-request or direct-message-start flow.
    // For now we will just show a snackbar
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Chat with ${m.displayName}')));
  }

  /// The explanation that comes BEFORE the OS permission sheet. Wording is
  /// deliberate: it says what we read (contacts), what we do with it (look
  /// for existing members) and what we show (public profiles), and it makes
  /// both outcomes equally easy to choose.
  Widget _consentCard(AzamanColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_outline, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Find your people on Azaman',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Connect with people you already know. With your permission, '
            "we'll check your contacts for existing Azaman members and show "
            'you their public profiles.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _loading ? null : _findPeople,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Enable contacts'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _notNow,
                child: Text(
                  'Not now',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One line that says what actually happened. Never a cheerful "no matches"
  /// when the request failed or the permission was declined.
  Widget _discoveryNote(AzamanColors colors) {
    final (String text, bool isError, bool retryable) = switch (_status) {
      ContactDiscoveryStatus.permissionDenied => (
        'Contacts access is off. You can turn it on whenever you like.',
        false,
        true,
      ),
      ContactDiscoveryStatus.noNumbers => (
        'No phone numbers were found in your contacts.',
        false,
        false,
      ),
      ContactDiscoveryStatus.failed => (
        _statusMessage ?? 'Contact discovery failed.',
        true,
        true,
      ),
      ContactDiscoveryStatus.ok =>
        _matched.isEmpty
            ? (
                'None of your contacts are on Azaman yet. Invite someone below.',
                false,
                true,
              )
            : ('', false, false),
      null => ('', false, false),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isError ? colors.danger : colors.textTertiary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          if (retryable)
            TextButton(
              onPressed: _loading ? null : _findPeople,
              child: Text(
                'Retry',
                style: TextStyle(color: colors.accent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

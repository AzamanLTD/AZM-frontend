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
  bool _loading = true;
 
  @override
  void initState() { super.initState(); _load(); }
 
  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ContactService.instance.getRecent(),
      ContactService.instance.syncDeviceContacts(),
    ]);
    setState(() {
      _recent = results[0] as List<RecentContact>;
      _matched = results[1] as List<MatchedContact>;
      _loading = false;
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
      body: SafeArea(child: _loading
        ? Center(child: CircularProgressIndicator(color: colors.accent))
        : CustomScrollView(slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent, pinned: false, floating: true,
              title: Text('Contacts', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
              actions: [
                TextButton(onPressed: _invite, child: Row(children: [
                  Icon(Icons.person_add_alt, color: colors.accent, size: 16),
                  const SizedBox(width: 4),
                  Text('Invite', style: TextStyle(color: colors.accent, fontWeight: FontWeight.w700)),
                ])),
              ],
            ),
            if (_recent.isNotEmpty) SliverToBoxAdapter(child: SizedBox(
              height: 92,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _recent.length,
                itemBuilder: (_, i) {
                  final c = _recent[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Column(children: [
                      StoryRing(avatarUrl: c.profilePictureUrl, hasUnseenStory: false, isBoosted: false, size: 56),
                      const SizedBox(height: 6),
                      SizedBox(width: 56, child: Text(c.username, textAlign: TextAlign.center,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textSecondary, fontSize: 11))),
                    ]),
                  );
                },
              ),
            )),
            SliverPadding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 4), sliver: SliverToBoxAdapter(
              child: Text('On Azaman', style: TextStyle(color: colors.textTertiary, fontWeight: FontWeight.w700, fontSize: 12)),
            )),
            SliverList(delegate: SliverChildBuilderDelegate((_, i) {
              final m = _matched[i];
              return ListTile(
                leading: StoryRing(avatarUrl: m.profilePictureUrl, hasUnseenStory: false, isBoosted: false, size: 46),
                title: Text(m.username, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                trailing: IconButton(
                  icon: Icon(Icons.chat_bubble_outline, color: colors.accent),
                  onPressed: () => _openChat(m),
                ),
              );
            }, childCount: _matched.length)),
          ]),
      ),
    );
  }
 
  void _openChat(MatchedContact m) {
    // Navigate to / create a friendship + push PersonalChatInterface,
    // reusing your existing friend-request or direct-message-start flow.
    // For now we will just show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chat with ${m.username}')));
  }
}

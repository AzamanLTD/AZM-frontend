// =============================================================================
// GROUP LIST SCREEN  (Master Sprint, 2026-05-27)
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/group_chat/group_chat_screen.dart';
import 'package:azaman/screens/group_chat/group_create_screen.dart';
import 'package:azaman/widgets/nav_transitions.dart';


class GroupListScreen extends ConsumerWidget {
  const GroupListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final groupsAsync = ref.watch(groupListProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Groups',
            style: TextStyle(
                color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: colors.accent,
        backgroundColor: colors.card,
        onRefresh: () => ref.read(groupListProvider.notifier).refresh(),
        child: groupsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
          error: (e, _) => Center(child: Text(e.toString())),
          data: (groups) {
            if (groups.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.person_add_outlined, size: 56, color: colors.textTertiary),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No groups yet',
                      style: TextStyle(
                          color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Create a group to chat with friends. Enable Susu to run a rotational savings cycle.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textTertiary, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: groups.length,
              itemBuilder: (context, i) {
                final g = groups[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _GroupTile(
                    group: g,
                    colors: colors,
                    onTap: () => pushWithVerticalTransition(context, GroupChatScreen(groupId: g.id)),
                  )
                      .animate()
                      .fadeIn(delay: (i * 50).ms, duration: 280.ms)
                      .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          pushWithVerticalTransition(context, const GroupCreateScreen());
        },
        backgroundColor: colors.accent,
        foregroundColor: colors.isDark ? Colors.black : Colors.white,
        icon: const Icon(Icons.person_add_outlined, size: 18),
        label: const Text('New Group',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final GroupSummary group;
  final AzamanColors colors;
  final VoidCallback onTap;
  const _GroupTile({required this.group, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.card.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.divider, width: 0.7),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        colors.accent.withValues(alpha: 0.30),
                        colors.accent.withValues(alpha: 0.10),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    group.name.isEmpty ? 'G' : group.name[0].toUpperCase(),
                    style: TextStyle(
                      color: colors.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (group.isSusuEnabled) ...[
                            const SizedBox(width: 6),
                            _SusuChip(group: group, colors: colors),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.members.length} members',
                        style: TextStyle(color: colors.textTertiary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: colors.textTertiary, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SUSU CHIP — Phase 5 / Workstream D (2026-06-01)
//
// Group-list chip marking a group's Susu state: a warning-colored
// "SUSU · <countdown>" while the initiation window is open, or a green
// "SUSU" once the Susu is active.
// =============================================================================
class _SusuChip extends StatelessWidget {
  final GroupSummary group;
  final AzamanColors colors;
  const _SusuChip({required this.group, required this.colors});

  String? _countdown() {
    final d = group.initiationDeadline;
    if (d == null) return null;
    final diff = d.difference(DateTime.now());
    if (diff.isNegative) return 'ending';
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    return '${diff.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final configuring = group.isSusuConfiguring;
    final color = configuring ? colors.warning : colors.success;
    final label = configuring ? 'SUSU · ${_countdown() ?? 'soon'}' : 'SUSU';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (configuring) ...[
            Icon(Icons.access_time, color: color, size: 8),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

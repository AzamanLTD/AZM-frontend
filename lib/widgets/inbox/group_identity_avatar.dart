/// Group identity avatar for inbox rows (Overhaul 04 §5; 07 §4.1 fills in the
/// full member orbit). Minimal C1 version: the existing bubble logic moved out
/// of the hub, plus a Susu ring when a Susu cycle is active or configuring.
library;

import 'package:flutter/material.dart';

import 'package:azaman/providers/group_chat_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

class GroupIdentityAvatar extends StatelessWidget {
  final GroupSummary group;
  final AzamanColors colors;
  final double size;

  const GroupIdentityAvatar({
    super.key,
    required this.group,
    required this.colors,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final core = _core();
    if (!group.isSusuEnabled) return SizedBox(width: size, height: size, child: core);
    final ringColor = group.isSusuActive ? colors.accent : colors.textTertiary;
    return Container(
      key: ValueKey(group.isSusuActive ? 'group_susu_ring_active' : 'group_susu_ring_configuring'),
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
      child: core,
    );
  }

  Widget _core() {
    final inner = group.isSusuEnabled ? size - 8 : size;
    final url = group.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: AzamanNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: inner,
          height: inner,
          placeholder: (_, __) => _gradientBubble(group.name, inner),
          errorWidget: (_, __, ___) => _gradientBubble(group.name, inner),
        ),
      );
    }
    final members = group.members;
    final big = inner * 0.6;
    final small = inner * 0.48;
    return SizedBox(
      width: inner,
      height: inner,
      child: Stack(
        children: [
          Positioned(top: 0, left: inner * 0.16, child: _gradientBubble(group.name, big)),
          if (members.isNotEmpty)
            Positioned(
              bottom: 2,
              left: 0,
              child: _memberBubble(
                members.first.profilePictureUrl,
                members.first.username ?? '?',
                small,
                colors.accentSecondary,
              ),
            ),
          if (members.length > 1)
            Positioned(
              bottom: 0,
              right: 2,
              child: _memberBubble(
                members[1].profilePictureUrl,
                members[1].username ?? '+',
                small,
                colors.success,
              ),
            )
          else if (members.length == 1)
            Positioned(bottom: 0, right: 2, child: _countBubble('+', small, colors.success)),
        ],
      ),
    );
  }

  Widget _gradientBubble(String name, double d) {
    final initial = name.trim().isEmpty ? '#' : name.trim()[0].toUpperCase();
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [colors.accent, colors.accentSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: colors.surface, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: colors.isDark ? Colors.black : Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: d * 0.42,
        ),
      ),
    );
  }

  Widget _memberBubble(String? url, String name, double d, Color fallback) {
    if (url != null && url.isNotEmpty) {
      return Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.surface, width: 2),
        ),
        child: ClipOval(
          child: AzamanNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: d,
            height: d,
            placeholder: (_, __) => _countBubble(name.isEmpty ? '?' : name[0].toUpperCase(), d - 4, fallback),
            errorWidget: (_, __, ___) => _countBubble(name.isEmpty ? '?' : name[0].toUpperCase(), d - 4, fallback),
          ),
        ),
      );
    }
    return _countBubble(name.isEmpty ? '?' : name[0].toUpperCase(), d, fallback);
  }

  Widget _countBubble(String char, double d, Color color) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: colors.surface, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          char,
          style: TextStyle(
            color: colors.isDark ? Colors.black : Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: d * 0.4,
          ),
        ),
      );
}
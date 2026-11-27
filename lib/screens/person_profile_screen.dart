// lib/screens/person_profile_screen.dart
// =============================================================================
// A PERSON'S PUBLIC PROFILE — for someone you are not friends with yet.
//
// Reached from people search. It uses the same header as every profile and
// the public fields the backend serves (GET /friends/profile/:userId):
// photo, handle, verified, trades, completion rate, reviews, loyalty tier,
// member since. Money and messages need a friendship, so the one action
// here is Add friend (or the honest "Request sent").
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/widgets/profile/az_profile_header.dart';

/// The public fields of a person, as the backend serves them.
@immutable
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.username,
    this.profilePictureUrl,
    this.tradesCompleted = 0,
    this.completionRate = 0,
    this.positiveReviews = 0,
    this.negativeReviews = 0,
    this.isVerified = false,
    this.loyaltyTier,
    this.memberSince,
  });

  final int id;
  final String username;
  final String? profilePictureUrl;
  final int tradesCompleted;
  final double completionRate;
  final int positiveReviews;
  final int negativeReviews;
  final bool isVerified;
  final String? loyaltyTier;
  final DateTime? memberSince;

  factory PublicProfile.fromJson(Map<String, dynamic> j) {
    num n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
    return PublicProfile(
      id: n(j['id']).toInt(),
      username: (j['username'] ?? '').toString(),
      profilePictureUrl: j['profilePictureUrl']?.toString(),
      tradesCompleted: n(j['tradesCompleted']).toInt(),
      completionRate: n(j['completionRate']).toDouble(),
      positiveReviews: n(j['positiveReviews']).toInt(),
      negativeReviews: n(j['negativeReviews']).toInt(),
      isVerified: j['isVerified'] == true,
      loyaltyTier: j['loyaltyTier']?.toString(),
      memberSince: DateTime.tryParse('${j['memberSince'] ?? ''}'),
    );
  }

  /// Completion rate as a percentage, accepting either 0..1 or 0..100.
  String get completionLabel {
    if (tradesCompleted == 0) return '—';
    final pct = completionRate <= 1 ? completionRate * 100 : completionRate;
    return '${pct.round()}%';
  }
}

/// Loads a public profile. Overridable for tests.
typedef PublicProfileLoader = Future<PublicProfile> Function(int userId);

Future<PublicProfile> loadPublicProfile(int userId) async {
  final res = await apiClient.get('/friends/profile/$userId');
  if (res.statusCode != 200) {
    throw Exception('Profile unavailable (${res.statusCode})');
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  return PublicProfile.fromJson(body['profile'] as Map<String, dynamic>);
}

class PersonProfileScreen extends ConsumerStatefulWidget {
  const PersonProfileScreen({
    super.key,
    required this.userId,
    required this.username,
    this.requestSent = false,
    this.onAddFriend,
    this.loader,
  });

  final int userId;

  /// Shown while the profile loads.
  final String username;

  /// A request is already pending from you.
  final bool requestSent;

  /// Opens the add-friend flow (the same one people search uses).
  final VoidCallback? onAddFriend;
  final PublicProfileLoader? loader;

  @override
  ConsumerState<PersonProfileScreen> createState() => _PersonProfileScreenState();
}

class _PersonProfileScreenState extends ConsumerState<PersonProfileScreen> {
  late Future<PublicProfile> _future = _load();

  /// Starts a load. A fast failure can land before the FutureBuilder has
  /// subscribed to the new future, so its error is marked as observed at
  /// once (`ignore` adds a discarding listener; the builder still gets it).
  Future<PublicProfile> _load() {
    final f = (widget.loader ?? loadPublicProfile)(widget.userId);
    f.ignore();
    return f;
  }

  void _retry() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: FutureBuilder<PublicProfile>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const Spacer(),
                  Text('Could not load this profile.', style: TextStyle(color: colors.textSecondary)),
                  TextButton(onPressed: _retry, child: const Text('Try again')),
                  const Spacer(),
                ],
              ),
            );
          }
          final p = snap.data;
          return SingleChildScrollView(
            child: AzProfileHeader(
              seed: widget.userId,
              name: p?.username ?? widget.username,
              handle: '@${p?.username ?? widget.username}',
              avatarUrl: p?.profilePictureUrl,
              verified: p?.isVerified ?? false,
              onBack: () => Navigator.of(context).maybePop(),
              chips: [
                if (p?.memberSince != null)
                  AzProfileChip(icon: Icons.calendar_today_outlined, label: 'Member since ${_monthYear(p!.memberSince!)}'),
                if (p?.loyaltyTier != null && p!.loyaltyTier!.isNotEmpty)
                  AzProfileChip(icon: Icons.workspace_premium_outlined, label: _title(p.loyaltyTier!)),
              ],
              stats: p == null
                  ? const []
                  : [
                      AzProfileStat(value: '${p.tradesCompleted}', label: 'Trades'),
                      AzProfileStat(value: p.completionLabel, label: 'Completion'),
                      AzProfileStat(value: '${p.positiveReviews}', label: 'Good reviews'),
                    ],
              actions: [
                AzProfileAction(
                  key: const ValueKey('person-add-friend'),
                  label: widget.requestSent ? 'Request sent' : 'Add friend',
                  icon: widget.requestSent ? Icons.schedule_rounded : Icons.person_add_alt_1_rounded,
                  primary: !widget.requestSent,
                  onTap: widget.requestSent ? null : widget.onAddFriend,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _monthYear(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  String _title(String raw) =>
      raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1).toLowerCase().replaceAll('_', ' ');
}

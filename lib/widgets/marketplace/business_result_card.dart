// =============================================================================
// AZAMAN — BUSINESS RESULT CARD (Workstream D, 2026-10-21)
//
// The marketplace listing card. Composition per the discovery-redesign
// spec:
//
//   • The business profile is a CIRCULAR avatar that cuts into the
//     rectangular card's leading edge — a designed, detached notch
//     (clip geometry is deterministic; see _NotchedCardClipper).
//   • A small circular badge at the avatar's bottom carries ONLY the
//     primary category ICON (accurate semantics; no category name
//     under the image). The canonical BusinessCategories mapping is
//     the single source of the icon.
//   • Tapping the CARD BODY opens the business's canonical profile
//     route directly. There is NO inline accordion/dropdown anymore.
//   • Tapping the AVATAR opens a compact action panel (follow /
//     bookmark / rate-and-review) wired to the real contracts:
//     GET /follows/check/:id + POST /follows + DELETE /follows/:id,
//     savedBusinessesProvider, LeaveReviewSheet. No action is faked.
//   • Bookmark does NOT appear on the card body — it lives on the
//     avatar panel.
//   • Beside the name only GROUNDED facts render: the category label,
//     verified badge, live open status and (when present) distance.
//     There is NO secondary-offering iconography: the business DTO
//     has no authoritative 'offered categories' field, and the spec
//     forbids guessing one (documented backend gap).
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/leave_review_sheet.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

// ── Published geometry (pinned by tests) ────────────────────────────────────

/// Circular avatar diameter.
const double kBusinessAvatarDiameter = 56.0;

/// Radial clearance between the avatar ring and the notch edge — the
/// "detached" air that makes the cutout read as designed, not accidental.
const double kBusinessNotchGap = 6.0;

/// The avatar's centre, measured from the CARD's leading edge and top.
const double kBusinessAvatarCenterInset = 44.0;

/// Circular category badge diameter.
const double kBusinessBadgeDiameter = 22.0;

// ── Live open-status (ported verbatim from the retired listing bar) ─────────

enum OpenStatus { open, closingSoon, closed, unknown }

/// Computes the business's live open state from its operating-hours map.
/// Unknown for missing/unparseable data — never a fabricated 'Open'.
OpenStatus currentOpenStatus(Map<String, dynamic>? hours) {
  if (hours == null || hours.isEmpty) return OpenStatus.unknown;
  final now = DateTime.now();
  final dayKey = [
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun',
  ][now.weekday - 1];
  final range = hours[dayKey]?.toString();
  if (range == null || range.isEmpty) return OpenStatus.unknown;
  final parts = range.split('-');
  if (parts.length != 2) return OpenStatus.unknown;
  final open = _parseTimeToday(parts[0].trim(), now);
  final close = _parseTimeToday(parts[1].trim(), now);
  if (open == null || close == null) return OpenStatus.unknown;
  if (now.isBefore(open) || now.isAfter(close)) return OpenStatus.closed;
  if (close.difference(now).inMinutes <= 30) return OpenStatus.closingSoon;
  return OpenStatus.open;
}

DateTime? _parseTimeToday(String t, DateTime now) {
  // Accept "H:mm" or "HH:mm" (24h). Also accept "H:mm AM/PM" loosely.
  t = t.toUpperCase().trim();
  bool pm = t.contains('PM');
  bool am = t.contains('AM');
  t = t.replaceAll(RegExp(r'[AP]M'), '').trim();
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
  if (m == null) return null;
  int hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  if (pm && hour < 12) hour += 12;
  if (am && hour == 12) hour = 0;
  return DateTime(now.year, now.month, now.day, hour, minute);
}

/// Card corner radius (matches the previous listing radius language).
const double kBusinessCardRadius = 16.0;

class BusinessResultCard extends ConsumerWidget {
  const BusinessResultCard({
    super.key,
    required this.business,
    this.distanceKm,
  });

  final BusinessProfile business;
  final double? distanceKm;

  // ── Navigation ────────────────────────────────────────────────────────

  void _openProfile(BuildContext context) {
    AzamanHaptics.nav();
    context.push('/business/${business.bizId}');
  }

  // ── Image sources (ported from the retired listing bar, unchanged) ───

  String? _avatarUrl(BusinessCategory cat) {
    if (business.logoUrl != null && business.logoUrl!.isNotEmpty) {
      return business.logoUrl;
    }
    if (business.showcaseUrls.isNotEmpty) return business.showcaseUrls.first;
    for (final prod in business.products) {
      if (prod.imageUrls.isNotEmpty) return prod.imageUrls.first;
    }
    return null; // no invented imagery: the placeholder glyph renders
  }

  Widget _avatarPlaceholder(BusinessCategory cat) => Container(
    color: cat.color.withValues(alpha: 0.12),
    alignment: Alignment.center,
    child: Icon(cat.icon, size: 26, color: cat.color.withValues(alpha: 0.55)),
  );

  // ── Grounded one-line facts ────────────────────────────────────────────

  String _subtitleLine(WidgetRef ref) {
    final following = ref.watch(followingListProvider).valueOrNull ?? [];
    if (following.any(
      (f) => f['businessProfileId']?.toString() == business.bizId,
    )) {
      return 'You follow this business';
    }
    if (business.description != null && business.description!.isNotEmpty) {
      return business.description!;
    }
    final products = business.products;
    switch (business.category) {
      case 'FOOD_BEVERAGE':
        return products.isNotEmpty
            ? '${products.length} item${products.length == 1 ? '' : 's'} on the menu'
            : 'Tap to browse the menu';
      case 'REAL_ESTATE':
      case 'HOSPITALITY':
        return 'Available rooms & pricing';
      case 'LOGISTICS':
        return 'Scheduled trips & seats';
      default:
        return products.isNotEmpty
            ? '${products.length} product${products.length == 1 ? '' : 's'} available'
            : BusinessCategories.fromWire(business.category).label;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final cat = BusinessCategories.fromWire(business.category);
    final url = _avatarUrl(cat);

    return Semantics(
      container: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        constraints: const BoxConstraints(minHeight: 88),
        // IntrinsicHeight bounds the Stack under the minHeight-only
        // constraint (a bare Stack would be unbounded in a ListView) while
        // still letting the card grow with large text instead of clipping.
        child: IntrinsicHeight(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── The notched rectangular body ─────────────────────────────
              // NON-positioned: under IntrinsicHeight its content height
              // sizes the card, so large text grows the card instead of
              // clipping. minWidth: infinity keeps it full-width under the
              // Stack's loose constraints.
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: double.infinity),
                child: PhysicalShape(
                  // The notch is subtracted from the card path itself, so
                  // both the fill and the elevation shadow carry the exact
                  // designed silhouette.
                  clipper: _NotchedCardClipper(
                    avatarCenter: const Offset(
                      kBusinessAvatarCenterInset,
                      kBusinessAvatarCenterInset,
                    ),
                    notchRadius:
                        kBusinessAvatarDiameter / 2 + kBusinessNotchGap,
                  ),
                  elevation: 1.5,
                  color: colors.card,
                  shadowColor: Colors.black.withValues(
                    alpha: colors.isDark ? 0.22 : 0.10,
                  ),
                  child: DecoratedBox(
                    // Subtle category hue tint, blended toward the card
                    // surface — same brand grammar as the previous bar.
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cat.color.withValues(
                            alpha: colors.isDark ? 0.08 : 0.05,
                          ),
                          colors.card,
                        ],
                        stops: const [0.0, 0.35],
                      ),
                    ),
                    child: Padding(
                      // Content clears the whole avatar + notch zone.
                      padding: const EdgeInsets.fromLTRB(84, 10, 12, 10),
                      child: _Body(
                        business: business,
                        cat: cat,
                        colors: colors,
                        subtitle: _subtitleLine(ref),
                        distanceKm: distanceKm,
                        onTap: () => _openProfile(context),
                      ),
                    ),
                  ),
                ),
              ),
              // ── The circular avatar (its own action surface) ─────────────
              PositionedDirectional(
                start: kBusinessAvatarCenterInset - kBusinessAvatarDiameter / 2,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _AvatarWithBadge(
                    bizId: business.bizId,
                    url: url,
                    cat: cat,
                    colors: colors,
                    placeholder: _avatarPlaceholder(cat),
                    onTap: () => _openActionPanel(context, business, colors),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card body (name + grounded signals + subtitle) ──────────────────────────

class _Body extends StatelessWidget {
  const _Body({
    required this.business,
    required this.cat,
    required this.colors,
    required this.subtitle,
    required this.distanceKm,
    required this.onTap,
  });

  final BusinessProfile business;
  final BusinessCategory cat;
  final AzamanColors colors;
  final String subtitle;
  final double? distanceKm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      key: ValueKey('business-card-body-${business.bizId}'),
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Open ${business.businessName}, ${cat.label}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    business.businessName,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colors.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Grounded signals only: category label, verified, live open
            // status, distance. NO star rating (records live on the
            // business surfaces), NO offering icons (no authoritative
            // DTO field — documented backend gap).
            Row(
              children: [
                Flexible(
                  child: Text(
                    cat.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (business.isVerified) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.verified_rounded, size: 13, color: colors.accent),
                ],
                if (business.locations.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: _OpenStatusPill(
                      colors: colors,
                      status: currentOpenStatus(
                        business.locations.first.operatingHours,
                      ),
                    ),
                  ),
                ],
                if (distanceKm != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${distanceKm!.toStringAsFixed(distanceKm! < 10 ? 1 : 0)} km',
                    style: TextStyle(fontSize: 11, color: colors.textTertiary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                color: colors.textTertiary,
                height: 1.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenStatusPill extends StatelessWidget {
  const _OpenStatusPill({required this.colors, required this.status});

  final AzamanColors colors;
  final OpenStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == OpenStatus.unknown) return const SizedBox.shrink();
    final (color, label) = switch (status) {
      OpenStatus.open => (Colors.green, 'Open'),
      OpenStatus.closingSoon => (Colors.orange, 'Closing soon'),
      OpenStatus.closed => (colors.textTertiary, 'Closed'),
      OpenStatus.unknown => (colors.textTertiary, ''), // unreachable guard
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
      ],
    );
  }
}

// ── Circular avatar with the primary-category badge ─────────────────────────

class _AvatarWithBadge extends StatelessWidget {
  const _AvatarWithBadge({
    required this.bizId,
    required this.url,
    required this.cat,
    required this.colors,
    required this.placeholder,
    required this.onTap,
  });

  final String bizId;
  final String? url;
  final BusinessCategory cat;
  final AzamanColors colors;
  final Widget placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = kBusinessAvatarDiameter;
    return Semantics(
      button: true,
      label: 'Actions for this business: follow, bookmark, or rate and review',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        key: ValueKey('business-avatar-$bizId'),
        onTap: () {
          AzamanHaptics.toggle();
          onTap();
        },
        child: SizedBox(
          width: d + kBusinessBadgeDiameter / 2,
          height: d + kBusinessBadgeDiameter / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The circular profile with its polished story-ring
              // treatment: card-surface gap ring + category accent.
              Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.card,
                  border: Border.all(color: cat.color, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: cat.color.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(2), // gap ring
                child: ClipOval(
                  child: url != null
                      ? AzamanNetworkImage(
                          imageUrl: url!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => placeholder,
                          errorWidget: (_, __, ___) => placeholder,
                        )
                      : placeholder,
                ),
              ),
              // The category badge: icon ONLY, accurate semantics, no
              // category name printed under the image.
              PositionedDirectional(
                key: ValueKey('business-avatar-badge-$bizId'),
                end: 0,
                bottom: 0,
                child: Container(
                  width: kBusinessBadgeDiameter,
                  height: kBusinessBadgeDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.card,
                    border: Border.all(
                      color: cat.color.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Semantics(
                    label: 'Category: ${cat.label}',
                    button: false,
                    child: Icon(cat.icon, size: 13, color: cat.color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── The notch clipper ────────────────────────────────────────────────────────

/// A rounded rectangle with a shallow semicircular bite subtracted from
/// the leading edge, centred on the avatar. Pure path arithmetic — no
/// painting, no layout side effects; deterministic at every width.
class _NotchedCardClipper extends CustomClipper<Path> {
  const _NotchedCardClipper({
    required this.avatarCenter,
    required this.notchRadius,
  });

  /// The avatar's centre in the CARD's coordinate space.
  final Offset avatarCenter;

  /// Avatar radius + the detached gap.
  final double notchRadius;

  @override
  Path getClip(Size size) {
    final card = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(kBusinessCardRadius),
        ),
      );
    final circle = Path()
      ..addOval(Rect.fromCircle(center: avatarCenter, radius: notchRadius));
    return Path.combine(PathOperation.difference, card, circle);
  }

  @override
  bool shouldReclip(_NotchedCardClipper oldClipper) =>
      oldClipper.avatarCenter != avatarCenter ||
      oldClipper.notchRadius != notchRadius;
}

// ── Avatar action panel (follow / bookmark / rate & review) ────────────────

Future<void> _openActionPanel(
  BuildContext context,
  BusinessProfile business,
  AzamanColors colors,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _BusinessActionPanel(business: business),
  );
}

class _BusinessActionPanel extends ConsumerStatefulWidget {
  const _BusinessActionPanel({required this.business});

  final BusinessProfile business;

  @override
  ConsumerState<_BusinessActionPanel> createState() =>
      _BusinessActionPanelState();
}

class _BusinessActionPanelState extends ConsumerState<_BusinessActionPanel> {
  bool _isFollowing = false;
  bool _followLoaded = false;
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _checkFollow();
  }

  String get _bizId => widget.business.bizId;

  Future<void> _checkFollow() async {
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get('/follows/check/$_bizId');
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _isFollowing = data['isFollowing'] ?? false;
        _followLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _followLoaded = true);
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    AzamanHaptics.toggle();
    final was = _isFollowing;
    setState(() {
      _isFollowing = !was;
      _followBusy = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      if (was) {
        await client.delete('/follows/$_bizId');
      } else {
        await client.post('/follows', {'businessProfileId': _bizId});
      }
    } catch (_) {
      // Honest failure: revert the optimistic state — never pretend a
      // follow/unfollow succeeded.
      if (mounted) setState(() => _isFollowing = was);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  void _toggleBookmark() {
    AzamanHaptics.toggle();
    ref.read(savedBusinessesProvider.notifier).toggle(_bizId);
  }

  Future<void> _review() async {
    final ctx = context;
    Navigator.of(ctx).pop();
    await LeaveReviewSheet.show(ctx, business: widget.business);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final saved = ref.watch(savedBusinessesProvider).contains(_bizId);
    final cat = BusinessCategories.fromWire(widget.business.category);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cat.color.withValues(alpha: 0.14),
                    border: Border.all(color: cat.color, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Icon(cat.icon, size: 20, color: cat.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.business.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _PanelRow(
            key: const ValueKey('business-action-follow'),
            icon: _isFollowing
                ? Icons.person_remove_rounded
                : Icons.person_add_alt_rounded,
            label: _isFollowing ? 'Unfollow' : 'Follow',
            busy: _followBusy || !_followLoaded,
            active: _isFollowing,
            colors: colors,
            onTap: _toggleFollow,
          ),
          _PanelRow(
            key: const ValueKey('business-action-bookmark'),
            icon: saved
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            label: saved ? 'Remove bookmark' : 'Bookmark',
            active: saved,
            colors: colors,
            onTap: _toggleBookmark,
          ),
          _PanelRow(
            key: const ValueKey('business-action-review'),
            icon: Icons.reviews_outlined,
            label: 'Rate & review',
            colors: colors,
            onTap: _review,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.busy = false,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final AzamanColors colors;
  final VoidCallback onTap;
  final bool busy;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52, // ≥44dp touch target
      child: ListTile(
        onTap: busy ? null : onTap,
        leading: busy
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.textTertiary,
                ),
              )
            : Icon(icon, color: active ? colors.accent : colors.textSecondary),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

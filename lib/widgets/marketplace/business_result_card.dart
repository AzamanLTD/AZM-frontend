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
//   • Beside the name only GROUNDED facts render: live open status and
//     (when present) distance. WORKSTREAM G (2026-10-25): the verified
//     badge and the marketing description are REMOVED from the list card
//     (verified stays on the business's own surfaces); the identity line
//     carries only real open-state, real distance and the category badge.
//     There is NO secondary-offering iconography: the business DTO
//     has no authoritative 'offered categories' field, and the spec
//     forbids guessing one (documented backend gap).
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/models/story_model.dart';
import 'package:azaman/providers/marketplace_extensions_provider.dart';
import 'package:azaman/screens/story_viewer_screen.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/providers/server_bookmarks_provider.dart'
    show isBusinessSaved, toggleBusinessSaved;
import 'package:azaman/services/recommendation_feedback_service.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/leave_review_sheet.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/azaman_network_image.dart';
import 'package:azaman/widgets/marketplace/profile_joystick.dart';
import 'package:azaman/widgets/marketplace/profile_joystick_delegates.dart';

// ── Published geometry (pinned by tests) ────────────────────────────────────

/// Circular avatar diameter.
const double kBusinessAvatarDiameter = 56.0;

/// Radial gap between the avatar circle and the story ring — the ring
/// floats clear of the photo instead of hugging it.
const double _kStoryRingGap = 3.5;

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

  // ── Joystick delegates (Workstream A) — real seams only ──────────────────

  /// The listing joystick's four directions, ALL wired to the real
  /// seams. Unavailable directions carry a null delegate: the satellite
  /// renders honestly dimmed and a release on it fires nothing.
  ProfileJoystickActions _joystickActions(
    BuildContext context,
    WidgetRef ref,
    BusinessProfile business, {
    required bool saved,
  }) {
    // MENU — the business's real catalog destination: the profile that
    // hosts the storefront catalog. Available only when the business
    // actually carries catalog content (products); the label is the
    // vertical-aware one ("Menu"/"Products"/...).
    final hasCatalog = business.products.isNotEmpty;
    // STORY — the AUTHORITATIVE story-state contract (the same signal
    // that draws the ring). No story state / no active story means the
    // satellite is honestly unavailable — never a guessed story.
    final hasActiveStory = business.storyState?.hasActiveStory == true;
    return ProfileJoystickActions(
      menu: ProfileJoystickAction(
        icon: Icons.menu_book_rounded,
        label: BusinessCategories.catalogLabel(business.category),
        onRelease: hasCatalog
            ? () {
                context.push('/business/${business.bizId}');
              }
            : null,
        unavailableLabel: 'No catalog yet',
      ),
      story: ProfileJoystickAction(
        icon: Icons.play_circle_outline_rounded,
        label: 'Story',
        onRelease: hasActiveStory
            ? () => openJoystickStory(context, ref, business)
            : null,
        unavailableLabel: 'No active story',
      ),
      bookmark: ProfileJoystickAction(
        icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        label: saved ? 'Saved' : 'Save',
        onRelease: () => toggleBusinessSaved(context, ref, business),
      ),
      showLess: ProfileJoystickAction(
        icon: Icons.visibility_off_outlined,
        label: 'Show less',
        // The release only OPENS the mandatory confirmation; the real
        // service call happens after an explicit confirm.
        onRelease: () => openJoystickShowLessConfirm(context, ref, business),
      ),
    );
  }

  // ── Grounded one-line facts ────────────────────────────────────────────

  String _subtitleLine(WidgetRef ref) {
    final following = ref.watch(followingListProvider).valueOrNull ?? [];
    if (following.any(
      (f) => f['businessProfileId']?.toString() == business.id,
    )) {
      return 'You follow this business';
    }
    // WORKSTREAM G (2026-10-25): the marketing description is REMOVED from
    // the list card — the identity line shows only grounded facts (follow
    // status, real inventory counts, category fallback).
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
                  clipper: const _NotchedCardClipper(
                    avatarCenter: Offset(
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
              // ── The circular avatar (its own action surface) ─────────────
              // WORKSTREAM A (2026-10-26): touch-down starts the SHARED
              // directional joystick — up opens the real catalog
              // destination (this card's is the business profile that
              // hosts the catalog), down opens the story viewer only when
              // the AUTHORITATIVE story state says a story is active,
              // right rides the durable bookmark seam, left opens the
              // MANDATORY show-less confirmation. A plain tap keeps the
              // existing action-panel behaviour.
              PositionedDirectional(
                start: kBusinessAvatarCenterInset - kBusinessAvatarDiameter / 2,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _AvatarWithBadge(
                    bizId: business.bizId,
                    saved: isBusinessSaved(ref, business),
                    url: url,
                    cat: cat,
                    colors: colors,
                    placeholder: _avatarPlaceholder(cat),
                    onTap: () => _openActionPanel(context, business, colors),
                    storyState: business.storyState,
                    joystickActions: _joystickActions(
                      context,
                      ref,
                      business,
                      saved: isBusinessSaved(ref, business),
                    ),
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

/// Workstream D: one coherent screen-reader utterance for the whole card
/// body — name, PRIMARY category, then the owner-DECLARED additional
/// offerings (from the offeredCategories contract, AZM-backend PR #366).
/// Mirrors exactly what is visually on the card: badge icon only for the
/// primary, chips only for declared offerings.
String _bodySemanticsLabel(BusinessProfile business, BusinessCategory cat) {
  // LEGACY-PAYLOAD DEFENSE: a malformed/legacy record may repeat the
  // primary category inside offeredCategories — the getter excludes it
  // (and dedupes), so the utterance mirrors the visual exactly: the
  // primary is spoken once via the badge label, never again as an
  // additional offering.
  final offerings = business.additionalOfferedCategories
      .map((w) => BusinessCategories.fromWire(w).label)
      .toList(growable: false);
  final base = 'Open ${business.businessName}, ${cat.label}';
  if (offerings.isEmpty) return base;
  return '$base, also offers ${offerings.join(', ')}';
}

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
        label: _bodySemanticsLabel(business, cat),
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
            // Grounded signals only: OFFERING ICONS from the owner-declared
            // offeredCategories contract (AZM-backend PR #366), verified,
            // live open status, distance. Workstream D: the PRIMARY category
            // is communicated ONLY by the circular avatar badge (icon +
            // semantics label) — no redundant text label here. NO star
            // rating (records live on the business surfaces). Empty
            // offeredCategories renders NO chips — that is a valid state.
            Row(
              children: [
                // LEGACY-PAYLOAD DEFENSE: chips render only ADDITIONAL
                // owner-declared offerings; a payload repeating the
                // primary category inside offeredCategories renders that
                // value ONLY as the avatar badge, never as a chip.
                if (business.additionalOfferedCategories.isNotEmpty) ...[
                  Flexible(
                    child: _OfferingChips(
                      wires: business.additionalOfferedCategories,
                      colors: colors,
                    ),
                  ),
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

// ── Offering chips (Workstream D / Workstream G) ────────────────────────────
// Rendered from the owner-DECLARED offeredCategories wire values only —
// never inferred from amenities/cuisine/description. WORKSTREAM G
// (2026-10-25): the icon + tint mapping is the CENTRAL
// BusinessCategories.offeringIconFor/offeringTintFor contract — no
// scattered per-widget maps that can drift from the canonical mapping.
/// Compact, non-interactive row of offering chips. Shows at most
/// [_OfferingChips.maxVisible] icons, then a "+N" text for the rest —
/// the Row it lives in is Flexible so long lists ellipsize, never
/// overflow. Wrapped in ONE semantics node so screen readers announce
/// "Also offers: Restaurants, Transit" instead of per-icon noise.
class _OfferingChips extends StatelessWidget {
  const _OfferingChips({required this.wires, required this.colors});

  static const int maxVisible = 3;

  final List<String> wires;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    // De-duped defensively (backend already dedupes) and order-preserving.
    final seen = <String>{};
    final unique = wires
        .where((w) => seen.add(w) && w.isNotEmpty)
        .toList(growable: false);
    if (unique.isEmpty) return const SizedBox.shrink();

    final visible = unique.take(maxVisible).toList(growable: false);
    final overflowCount = unique.length - visible.length;

    // NOTE: no Semantics wrapper here. The card body's semantics node
    // (excludeSemantics: true) already swallows descendant semantics, so
    // the OFFERINGS are announced in the body label itself
    // ('…, also offers Restaurants, Transit') — one coherent utterance,
    // never per-icon noise.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final wire in visible) ...[
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BusinessCategories.offeringTintFor(
                wire,
              ).withValues(alpha: 0.16),
            ),
            child: Icon(
              BusinessCategories.offeringIconFor(wire),
              size: 12,
              color: BusinessCategories.offeringTintFor(wire),
            ),
          ),
          if (wire != visible.last) const SizedBox(width: 4),
        ],
        if (overflowCount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '+$overflowCount',
            style: TextStyle(
              fontSize: 10,
              color: colors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
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

// ── Circular avatar: category badge at 6 o'clock + bookmark state ─────────
//
// WORKSTREAM G (2026-10-25):
//   • G3 — the primary-category badge moved from the bottom-RIGHT corner
//     to the 6 o'clock position: centred on the avatar's vertical axis,
//     its bottom edge flush with the avatar circle's bottom edge, cut out
//     of the photo by a card-surface moat so the logo stays dominant.
//   • G4 — the bookmark INDICATOR sits at the TOP-RIGHT of the profile
//     picture (never on the card body). It is a state signal, not a
//     button: it reflects the real savedBusinessesProvider (the app's
//     saved-business source of truth) and toggling stays in the avatar
//     action panel. No server bookmark contract exists, so the indicator
//     claims nothing beyond that provider's state.
class _AvatarWithBadge extends ConsumerWidget {
  const _AvatarWithBadge({
    required this.bizId,
    required this.saved,
    required this.url,
    required this.cat,
    required this.colors,
    required this.placeholder,
    required this.onTap,
    this.storyState,
    required this.joystickActions,
  });

  final String bizId;

  /// AUTHORITATIVE bookmark state from the durable seam
  /// (isBusinessSaved at the card) — the badge renders server truth,
  /// not the device-local wishlist.
  final bool saved;
  final String? url;
  final BusinessCategory cat;
  final AzamanColors colors;
  final Widget placeholder;
  final VoidCallback onTap;

  /// BUSINESS STORY STATE (AZM-backend PR #371) — the authoritative
  /// active/unseen signal. Null (legacy payload / backend without the
  /// contract) or hasActiveStory == false renders NO ring: absence is
  /// honest, never a guessed fallback.
  final BusinessStoryState? storyState;

  /// WORKSTREAM A — the shared directional joystick's delegate bundle
  /// (built by BusinessResultCard from the real seams).
  final ProfileJoystickActions joystickActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const d = kBusinessAvatarDiameter;
    // Story ring state — drawn ONLY from the authoritative block.
    // hasUnseenStory == null means the viewer is anonymous: the ring is
    // drawn WITHOUT unseen emphasis and the label never claims "new".
    final story = storyState;
    final hasRing = story != null && story.hasActiveStory;
    final unseen = hasRing && story.hasUnseenStory == true;
    final storyLabel = !hasRing
        ? ''
        : unseen
        ? ' New story'
        : ' Story';
    return Semantics(
      button: true,
      label: saved
          ? 'Actions for this business: follow, bookmark, or rate and '
                'review. Bookmarked$storyLabel'
          : 'Actions for this business: follow, bookmark, or rate and '
                'review$storyLabel',
      child: ProfileJoystick(
        key: ValueKey('business-avatar-$bizId'),
        actions: joystickActions,
        // Short-tap behaviour preserved: the action panel.
        onTap: () {
          AzamanHaptics.toggle();
          onTap();
        },
        child: SizedBox(
          width: d,
          height: d,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // BUSINESS STORY RING (AZM-backend PR #371) — drawn around
              // the avatar ONLY when the authoritative storyState says a
              // story is ACTIVE. Unseen emphasis (accent ring + 'New
              // story' semantics) ONLY on a real `true`; a seen story and
              // an anonymous null both draw the quiet seen ring — null
              // is NEVER treated as unseen.
              if (hasRing)
                PositionedDirectional(
                  key: ValueKey('business-story-ring-$bizId'),
                  start: -_kStoryRingGap,
                  end: -_kStoryRingGap,
                  top: -_kStoryRingGap,
                  bottom: -_kStoryRingGap,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: unseen ? colors.accent : colors.divider,
                          width: unseen ? 2.5 : 2.0,
                        ),
                      ),
                    ),
                  ),
                ),
              // The circular profile with its polished ring treatment:
              // card-surface gap ring + category accent.
              Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.card,
                  // REFERENCE FIDELITY — a distinct, BOLD category ring
                  // around the photo (the reference's ~3px accent ring).
                  // Flat by design: the reference carries no glow.
                  border: Border.all(color: cat.color, width: 3),
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
              // G3 — the category badge at 6 o'clock: centred on the
              // avatar's axis, bottom edge flush with the circle's
              // bottom edge, cut out of the photo by the card-surface
              // moat (the outer disc) so it reads as a designed cut-out,
              // not a sticker. Icon ONLY, accurate semantics, no
              // category name printed under the image.
              PositionedDirectional(
                key: ValueKey('business-avatar-badge-$bizId'),
                start: (d - kBusinessBadgeDiameter) / 2,
                bottom: 0,
                child: Container(
                  width: kBusinessBadgeDiameter,
                  height: kBusinessBadgeDiameter,
                  // The cut-out moat: card-surface separation between
                  // the badge and the photo behind it.
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.card,
                  ),
                  padding: const EdgeInsets.all(2), // moat ring
                  alignment: Alignment.center,
                  child: Semantics(
                    label: 'Category: ${cat.label}',
                    button: false,
                    child: Container(
                      width: kBusinessBadgeDiameter - 4,
                      height: kBusinessBadgeDiameter - 4,
                      // REFERENCE FIDELITY — the badge disc is WHITE
                      // with a DARK monochrome category glyph (#333 in
                      // the reference), in BOTH themes: a deliberately
                      // fixed high-contrast cut-out, like the reference
                      // photo's white disc. In dark mode the white
                      // disc pops against the photo; in light mode the
                      // moat ring keeps it separated from the surface.
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: colors.textTertiary.withValues(alpha: 0.4),
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        cat.icon,
                        size: 12,
                        color: const Color(0xFF333333),
                      ),
                    ),
                  ),
                ),
              ),
              // G4 — the bookmark indicator at the profile picture's
              // top-right: state signal only (toggling lives in the
              // avatar panel). Cut out of the photo by its own
              // card-surface moat.
              if (saved)
                PositionedDirectional(
                  key: ValueKey('business-avatar-bookmark-$bizId'),
                  end: 0,
                  top: 0,
                  child: Semantics(
                    label: 'Bookmarked',
                    button: false,
                    excludeSemantics: false,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.card,
                      ),
                      padding: const EdgeInsets.all(2), // moat ring
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.bookmark_rounded,
                        size: 11,
                        color: colors.accent,
                      ),
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

  // "SHOW LESS LIKE THIS" (AZM-backend PR #373) — persistent,
  // user-scoped recommendation feedback. The row appears ONLY after
  // the real check succeeds; a failed fetch renders NO row (honest
  // absence — the same grammar as the Watch-story affordance).
  bool? _showLessApplied; // null = unknown (check in flight/failed)
  bool _showLessBusy = false;

  // WORKSTREAM G (2026-10-25) — G5: the panel offers 'Watch story' ONLY
  // after the REAL stories contract (GET /marketplace/business/:id/stories)
  // returns at least one story that has not expired. No invented counts,
  // no fabricated existence: fetch failure and empty/expired lists render
  // NO row — an honest absence.
  List<BusinessStory>? _activeStories;

  @override
  void initState() {
    super.initState();
    _checkFollow();
    _checkStories();
    _checkShowLess();
  }

  /// Canonical BusinessProfile.id — the ONLY key the follow and
  /// recommendation-feedback contracts accept (display "BIZ-..." codes
  /// 404 against findUnique({ where: { id } })).
  String get _canonicalId => widget.business.id;

  Future<void> _checkStories() async {
    try {
      final stories = await ref
          .read(marketplaceBookingServiceProvider)
          .getBusinessStories(widget.business.bizId);
      if (!mounted) return;
      final now = DateTime.now();
      final active = stories
          .where((story) => story.expiresAt.isAfter(now))
          .toList(growable: false);
      setState(() => _activeStories = active);
    } catch (_) {
      // Honest failure: no Watch-story affordance on a failed fetch —
      // the error is never surfaced as 'no stories' either; the row is
      // simply absent.
      if (mounted) setState(() => _activeStories = const []);
    }
  }

  Future<void> _watchStory() async {
    final stories = _activeStories;
    if (stories == null || stories.isEmpty) return;
    final ctx = context;
    Navigator.of(ctx).pop();
    await StoryViewerScreen.open(
      ctx,
      groups: [storyGroupFromBusinessStories(stories)],
      initialGroupIndex: 0,
    );
  }

  Future<void> _checkFollow() async {
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get('/follows/check/$_canonicalId');
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
        await client.delete('/follows/$_canonicalId');
      } else {
        await client.post('/follows', {'businessProfileId': _canonicalId});
      }
    } catch (_) {
      // Honest failure: revert the optimistic state — never pretend a
      // follow/unfollow succeeded.
      if (mounted) setState(() => _isFollowing = was);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _checkShowLess() async {
    try {
      final applied = await ref
          .read(recommendationFeedbackServiceProvider)
          .check(_canonicalId);
      if (!mounted) return;
      setState(() => _showLessApplied = applied);
    } catch (_) {
      // Honest absence: no Show-less affordance on a failed check.
      if (mounted) setState(() => _showLessApplied = null);
    }
  }

  Future<void> _toggleShowLess() async {
    if (_showLessBusy || _showLessApplied == null) return;
    AzamanHaptics.toggle();
    final was = _showLessApplied!;
    setState(() => _showLessBusy = true);
    try {
      final service = ref.read(recommendationFeedbackServiceProvider);
      if (was == true) {
        final result = await service.undo(_canonicalId);
        if (!mounted) return;
        // ANY 200 means NONE — removed:false is idempotent success.
        if (result.none) {
          setState(() => _showLessApplied = false);
        } else {
          _showLessRejected('Could not undo. Still showing less.');
        }
      } else {
        final result = await service.apply(_canonicalId);
        if (!mounted) return;
        // alreadyApplied:true is SUCCESS — the durable state is
        // SHOW_LESS either way.
        if (result.showLess) {
          setState(() => _showLessApplied = true);
        } else {
          _showLessRejected('Could not apply. Nothing changed.');
        }
      }
    } catch (_) {
      // Honest failure: the durable state never moved — revert to it.
      _showLessRejected(
        was == true
            ? 'Could not undo. Still showing less.'
            : 'Could not apply. Nothing changed.',
      );
    } finally {
      if (mounted) setState(() => _showLessBusy = false);
    }
  }

  void _showLessRejected(String message) {
    if (!mounted) return;
    setState(() => _showLessApplied = _showLessApplied); // state unchanged
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _toggleBookmark() async {
    AzamanHaptics.toggle();
    // The durable seam: real sessions ride the server bookmark
    // contract (canonical ids, exact rollback); demo keeps the
    // device-local wishlist. Failure surfaces via the seam's snackbar.
    await toggleBusinessSaved(context, ref, widget.business);
  }

  Future<void> _review() async {
    final ctx = context;
    Navigator.of(ctx).pop();
    await LeaveReviewSheet.show(ctx, business: widget.business);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final saved = isBusinessSaved(ref, widget.business);
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
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_activeStories != null && _activeStories!.isNotEmpty)
                    _PanelRow(
                      key: const ValueKey('business-action-watch-story'),
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Watch story',
                      colors: colors,
                      onTap: _watchStory,
                    ),
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
                  if (_showLessApplied != null)
                    _PanelRow(
                      key: const ValueKey('business-action-show-less'),
                      icon: Icons.visibility_off_outlined,
                      label: _showLessApplied!
                          ? 'Undo "show less like this"'
                          : 'Show less like this',
                      busy: _showLessBusy,
                      active: _showLessApplied!,
                      colors: colors,
                      onTap: _toggleShowLess,
                    ),
                ],
              ),
            ),
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

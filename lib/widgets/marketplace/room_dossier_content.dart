// =============================================================================
// ROOM DOSSIER CONTENT — floor-plan-first room detail (TASK-015)
//
// The blueprint's detailPresentation for hotels is `roomDossier`. This file is
// the CONTENT the shared `MarketplaceDossierSheet` (TASK-011) renders — the
// scaffold, handle, eyebrow and glass substrate all come from TASK-011; this
// file only supplies the body:
//
//   1. a mini floor plan with the tapped room's footprint highlighted and
//      springing in,
//   2. a horizontal gallery with drag-to-explore parallax (the image layer
//      drifts at 0.75× the page velocity while the caption rides at full
//      velocity),
//   3. a spec sheet — capacity / floor / bed / type / amenities — as a grid
//      of glyph+label cells. Never a Chip.
//
// The amenity icon mapper deliberately mirrors the booking screen's private
// `_hotelAmenityIcon` (that screen deletes its copy in this task); a shared
// export would have touched the screen's internals for no behavioural gain.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/models/hotel_models.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/widgets/azaman_network_image.dart';

IconData _amenityIcon(String amenity) {
  final a = amenity.toLowerCase();
  if (a.contains('wifi') || a.contains('internet')) return Icons.wifi;
  if (a.contains('ac') || a.contains('air')) return Icons.ac_unit;
  if (a.contains('tv')) return Icons.tv;
  if (a.contains('pool') || a.contains('spa')) return Icons.pool;
  if (a.contains('gym') || a.contains('fitness')) return Icons.fitness_center;
  if (a.contains('breakfast')) return Icons.free_breakfast;
  if (a.contains('parking')) return Icons.local_parking;
  if (a.contains('balcony') || a.contains('terrace')) return Icons.balcony;
  if (a.contains('kitchen')) return Icons.kitchen;
  if (a.contains('bar')) return Icons.local_bar;
  if (a.contains('pet')) return Icons.pets;
  if (a.contains('smoke')) return Icons.smoke_free;
  return Icons.check_circle_outline;
}

class RoomDossierContent extends StatelessWidget {
  final HotelRoom room;
  final List<HotelRoom> floorMates;
  final AzamanColors colors;

  const RoomDossierContent({
    super.key,
    required this.room,
    required this.floorMates,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlanHero(room: room, floorMates: floorMates, colors: colors),
        if (room.imageUrls.isNotEmpty) ...[
          const SizedBox(height: AzSpace.md),
          _ParallaxGallery(
            images: room.imageUrls,
            roomNumber: room.roomNumber,
            colors: colors,
          ),
        ],
        const SizedBox(height: AzSpace.md),
        Text('ROOM SPEC',
            style: AzText.eyebrow.copyWith(color: colors.textTertiary)),
        const SizedBox(height: AzSpace.sm),
        _specGrid(),
        if (room.amenities.isNotEmpty) ...[
          const SizedBox(height: AzSpace.md),
          Text('AMENITIES',
              style: AzText.eyebrow.copyWith(color: colors.textTertiary)),
          const SizedBox(height: AzSpace.sm),
          _amenityGrid(),
        ],
      ],
    );
  }

  Widget _specGrid() {
    return Wrap(
      spacing: AzSpace.sm,
      runSpacing: AzSpace.sm,
      children: [
        _SpecCell(
          icon: Icons.people_outline,
          label: 'Capacity',
          value: '${room.capacity} guest${room.capacity == 1 ? '' : 's'}',
          colors: colors,
        ),
        _SpecCell(
          icon: Icons.stairs_outlined,
          label: 'Floor',
          value: room.floor == null ? '—' : '${room.floor}',
          colors: colors,
        ),
        _SpecCell(
          icon: Icons.bed_outlined,
          label: 'Bed',
          value: room.bedConfig ?? room.displayType,
          colors: colors,
        ),
        _SpecCell(
          icon: Icons.meeting_room_outlined,
          label: 'Type',
          value: room.displayType,
          colors: colors,
        ),
      ],
    );
  }

  Widget _amenityGrid() {
    return Wrap(
      spacing: AzSpace.sm,
      runSpacing: AzSpace.sm,
      children: [
        for (final amenity in room.amenities.take(8))
          _SpecCell(
            icon: _amenityIcon(amenity),
            label: amenity,
            value: '',
            colors: colors,
          ),
      ],
    );
  }
}

class _SpecCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AzamanColors colors;

  const _SpecCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      padding: const EdgeInsets.all(AzSpace.sm),
      decoration: BoxDecoration(
        color: colors.softSurface.withValues(alpha: 0.6),
        borderRadius: AzRadius.brMd,
        border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.accent),
          const SizedBox(height: AzSpace.xs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AzText.caption.copyWith(color: colors.textTertiary),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(height: AzSpace.xxs),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AzText.bodyS.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanHero extends StatelessWidget {
  final HotelRoom room;
  final List<HotelRoom> floorMates;
  final AzamanColors colors;

  const _PlanHero({
    required this.room,
    required this.floorMates,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = [...floorMates]..sort((a, b) {
        final na = int.tryParse(a.roomNumber) ?? 0;
        final nb = int.tryParse(b.roomNumber) ?? 0;
        return na.compareTo(nb);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.map_outlined, size: 15, color: colors.textTertiary),
            const SizedBox(width: AzSpace.xs),
            Text('FLOOR PLAN',
                style: AzText.eyebrow.copyWith(color: colors.textTertiary)),
            const Spacer(),
            Text(
              room.floor == null ? 'Ground level' : 'Floor ${room.floor}',
              style: AzText.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: AzSpace.sm),
        Container(
          height: 148,
          width: double.infinity,
          padding: const EdgeInsets.all(AzSpace.md),
          decoration: BoxDecoration(
            color: colors.softSurface.withValues(alpha: 0.5),
            borderRadius: AzRadius.brLg,
            border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final mate in ordered) ...[
                  _PlanFootprint(
                    room: mate,
                    focused: mate.id == room.id,
                    colors: colors,
                  ),
                  const SizedBox(width: AzSpace.sm),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanFootprint extends StatelessWidget {
  final HotelRoom room;
  final bool focused;
  final AzamanColors colors;

  const _PlanFootprint({
    required this.room,
    required this.focused,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final bookable = room.isBookable;
    final tile = Container(
      width: 56,
      height: 92,
      padding: const EdgeInsets.all(AzSpace.xs),
      decoration: BoxDecoration(
        color: focused
            ? colors.accent.withValues(alpha: 0.14)
            : bookable
                ? colors.surface
                : colors.card.withValues(alpha: 0.5),
        borderRadius: AzRadius.brSm,
        border: Border.all(
          color: focused
              ? colors.accent
              : colors.divider.withValues(alpha: 0.55),
          width: focused ? 1.5 : 0.8,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(
            bookable ? Icons.bed_outlined : Icons.lock_outline,
            size: 14,
            color: focused ? colors.accent : colors.textTertiary,
          ),
          Text(
            room.roomNumber,
            style: AzText.label.copyWith(
              color: focused ? colors.accent : colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            bookable
                ? '\$${room.basePriceUsdc.toStringAsFixed(0)}'
                : '—',
            style: AzText.caption.copyWith(
              color: colors.textTertiary,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
    if (!focused) return tile;
    return Semantics(
      label: 'Room ${room.roomNumber} is highlighted on the floor plan',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.9, end: 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutBack,
        builder: (context, value, child) =>
            Transform.scale(scale: value, child: child),
        child: tile,
      ),
    );
  }
}

class _ParallaxGallery extends StatefulWidget {
  final List<String> images;
  final String roomNumber;
  final AzamanColors colors;

  const _ParallaxGallery({
    required this.images,
    required this.roomNumber,
    required this.colors,
  });

  @override
  State<_ParallaxGallery> createState() => _ParallaxGalleryState();
}

class _ParallaxGalleryState extends State<_ParallaxGallery> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 160,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final page = _controller.hasClients &&
                      _controller.position.hasContentDimensions
                  ? _controller.page ?? 0.0
                  : 0.0;
              return PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: widget.images.length,
                itemBuilder: (context, index) {
                  final drift = (page - index).clamp(-1.0, 1.0).toDouble();
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Parallax layer: the image drifts slower than the page.
                      Transform.translate(
                        offset: Offset(-drift * 26, 0),
                        child: Transform.scale(
                          scale: 1.08,
                          child: ClipRRect(
                            borderRadius: AzRadius.brLg,
                            child: AzamanNetworkImage(
                              imageUrl: widget.images[index],
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      // Caption rides at full page velocity.
                      Positioned(
                        left: AzSpace.md,
                        bottom: AzSpace.md,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AzSpace.sm, vertical: AzSpace.xs),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: AzRadius.brPill,
                          ),
                          child: Text(
                            'Room ${widget.roomNumber} · '
                            '${index + 1}/${widget.images.length}',
                            style: AzText.caption
                                .copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: AzSpace.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.images.length; i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _index
                      ? widget.colors.accent
                      : widget.colors.divider,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

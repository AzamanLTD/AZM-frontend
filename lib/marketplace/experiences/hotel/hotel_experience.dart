import 'package:flutter/material.dart';

import 'package:azaman/theme/motion_tokens.dart';

class HotelRoom {
  final String id;
  final String name;
  final String? floor;
  final String? description;
  final double? nightlyRate;
  final String? currency;
  final int? capacity;
  final List<String> amenities;
  final List<String> imageUrls;
  final bool available;

  const HotelRoom({
    required this.id,
    required this.name,
    this.floor,
    this.description,
    this.nightlyRate,
    this.currency,
    this.capacity,
    this.amenities = const [],
    this.imageUrls = const [],
    this.available = true,
  });

  factory HotelRoom.fromJson(Map<String, dynamic> json) {
    final rawAmenities = json['amenities'];
    final rawImages = json['imageUrls'] ?? json['images'];
    final rate = json['nightlyRate'] ?? json['price'] ?? json['pricePerNight'];
    return HotelRoom(
      id: (json['id'] ?? json['roomId'] ?? '').toString(),
      name: (json['name'] ?? json['roomName'] ?? 'Room').toString(),
      floor: json['floor']?.toString(),
      description: json['description']?.toString(),
      nightlyRate: rate is num ? rate.toDouble() : double.tryParse(rate?.toString() ?? ''),
      currency: json['currency']?.toString(),
      capacity: json['capacity'] is num ? (json['capacity'] as num).toInt() : int.tryParse(json['capacity']?.toString() ?? ''),
      amenities: rawAmenities is List ? rawAmenities.map((e) => e.toString()).where((e) => e.isNotEmpty).toList(growable: false) : const [],
      imageUrls: rawImages is List ? rawImages.map((e) => e.toString()).where((e) => e.isNotEmpty).toList(growable: false) : const [],
      available: json['available'] != false && json['isAvailable'] != false,
    );
  }

  String get formattedRate {
    if (nightlyRate == null) return 'Rate unavailable';
    final symbol = switch (currency?.toUpperCase()) {
      'GHS' => 'GH₵',
      'NGN' => '₦',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => currency?.isNotEmpty == true ? '${currency!} ' : '',
    };
    return '$symbol${nightlyRate!.toStringAsFixed(2)} / night';
  }
}

class HotelRoomExplorer extends StatelessWidget {
  final List<HotelRoom> rooms;
  final ValueChanged<HotelRoom> onRoomSelected;

  const HotelRoomExplorer({super.key, required this.rooms, required this.onRoomSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rooms.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('No rooms available for the selected dates.'));
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final room = rooms[index];
        final image = room.imageUrls.isEmpty ? null : room.imageUrls.first;
        return Semantics(
          button: true,
          label: '${room.name}, ${room.formattedRate}',
          child: Material(
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: theme.dividerColor)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: room.available ? () => onRoomSelected(room) : null,
              child: Row(
                children: [
                  SizedBox(
                    width: 124,
                    height: 132,
                    child: image == null
                        ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: const Icon(Icons.hotel_outlined))
                        : Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.hotel_outlined)),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(room.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        if (room.floor != null) Text('Floor ${room.floor}', style: theme.textTheme.bodySmall),
                        if (room.capacity != null) Text('Up to ${room.capacity} guests', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 5),
                        Text(room.available ? room.formattedRate : 'Unavailable', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: room.available ? theme.colorScheme.primary : theme.colorScheme.error)),
                      ]),
                    ),
                  ),
                  Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showHotelRoomDetail(BuildContext context, {required HotelRoom room, required ValueChanged<HotelRoom> onBook}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(room.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))), IconButton(tooltip: 'Close', onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close))]),
            if (room.imageUrls.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(18), child: AspectRatio(aspectRatio: 1.7, child: Image.network(room.imageUrls.first, fit: BoxFit.cover))),
            const SizedBox(height: 12),
            Text(room.formattedRate, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (room.description?.isNotEmpty == true) ...[const SizedBox(height: 8), Text(room.description!)],
            if (room.amenities.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 6, runSpacing: 6, children: room.amenities.take(8).map((a) => Chip(label: Text(a), visualDensity: VisualDensity.compact)).toList())],
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: room.available ? () { Navigator.of(sheetContext).pop(); onBook(room); } : null, child: Text(room.available ? 'Select room' : 'Unavailable'))),
          ]),
        ),
      ),
    ),
  );
}

// =============================================================================
// AZAMAN — Order Tracking Screen (Phase 3)
//
// Real-time order tracking with a live courier map, ETA countdown,
// status timeline, and driver info. Uses Google Maps Flutter for the map
// with custom markers for courier + delivery location.
//
// Reference: Uber Eats tracker, DoorDash live map
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/services/api_client.dart';

// ── Providers ───────────────────────────────────────────────────────────────

final orderTrackingProvider = FutureProvider.family<OrderTracking, String>((ref, orderId) async {
  final res = await apiClient.get('/orders/$orderId/tracking');
  if (res.statusCode != 200) throw Exception('Failed to load tracking');
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  if (body['tracking'] == null) throw Exception('Tracking not available');
  return OrderTracking.fromJson(body['tracking'] as Map<String, dynamic>);
});

final orderTimelineProvider = FutureProvider.family<List<TimelineEvent>, String>((ref, orderId) async {
  final res = await apiClient.get('/orders/$orderId/tracking/timeline');
  if (res.statusCode != 200) return [];
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final list = body['timeline'] as List<dynamic>? ?? [];
  return list.map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>)).toList();
});

// ── Models ──────────────────────────────────────────────────────────────────

class OrderTracking {
  final String id;
  final String orderId;
  final double? courierLatitude;
  final double? courierLongitude;
  final double? courierHeading;
  final double? courierSpeedKmh;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? deliveryAddress;
  final DateTime? estimatedArrival;
  final DateTime? actualArrival;
  final List<dynamic> timeline;
  final String? driverName;
  final String? driverPhone;
  final String? vehiclePlate;
  final DateTime? lastPingAt;

  OrderTracking({
    required this.id,
    required this.orderId,
    this.courierLatitude,
    this.courierLongitude,
    this.courierHeading,
    this.courierSpeedKmh,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.deliveryAddress,
    this.estimatedArrival,
    this.actualArrival,
    this.timeline = const [],
    this.driverName,
    this.driverPhone,
    this.vehiclePlate,
    this.lastPingAt,
  });

  factory OrderTracking.fromJson(Map<String, dynamic> j) => OrderTracking(
        id: j['id'] as String,
        orderId: j['orderId'] as String,
        courierLatitude: j['courierLatitude'] != null ? (j['courierLatitude'] as num).toDouble() : null,
        courierLongitude: j['courierLongitude'] != null ? (j['courierLongitude'] as num).toDouble() : null,
        courierHeading: j['courierHeading'] != null ? (j['courierHeading'] as num).toDouble() : null,
        courierSpeedKmh: j['courierSpeedKmh'] != null ? (j['courierSpeedKmh'] as num).toDouble() : null,
        deliveryLatitude: j['deliveryLatitude'] != null ? (j['deliveryLatitude'] as num).toDouble() : null,
        deliveryLongitude: j['deliveryLongitude'] != null ? (j['deliveryLongitude'] as num).toDouble() : null,
        deliveryAddress: j['deliveryAddress'] as String?,
        estimatedArrival: j['estimatedArrival'] != null ? DateTime.tryParse(j['estimatedArrival']) : null,
        actualArrival: j['actualArrival'] != null ? DateTime.tryParse(j['actualArrival']) : null,
        timeline: j['timeline'] as List<dynamic>? ?? [],
        driverName: j['driverName'] as String?,
        driverPhone: j['driverPhone'] as String?,
        vehiclePlate: j['vehiclePlate'] as String?,
        lastPingAt: j['lastPingAt'] != null ? DateTime.tryParse(j['lastPingAt']) : null,
      );
}

class TimelineEvent {
  final String status;
  final String note;
  final DateTime timestamp;

  TimelineEvent({required this.status, required this.note, required this.timestamp});

  factory TimelineEvent.fromJson(Map<String, dynamic> j) => TimelineEvent(
        status: j['status'] as String,
        note: j['note'] as String? ?? '',
        timestamp: DateTime.parse(j['timestamp'] as String),
      );
}

// ── Screen ──────────────────────────────────────────────────────────────────

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String orderRef;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    this.orderRef = '',
  });

  @override
  ConsumerState<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  LatLng? _courierPos;
  LatLng? _deliveryPos;
  CameraPosition? _initialCamera;

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final tracking = ref.watch(orderTrackingProvider(widget.orderId));
    final timeline = ref.watch(orderTimelineProvider(widget.orderId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.card,
        title: Text('Track Order${widget.orderRef.isNotEmpty ? ' ${widget.orderRef}' : ''}',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: colors.textPrimary),
        elevation: 0,
      ),
      body: tracking.when(
        loading: () => Center(child: CircularProgressIndicator(color: colors.accent)),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off, size: 64, color: colors.textSecondary),
              const SizedBox(height: 16),
              Text(err.toString(), style: TextStyle(color: colors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(orderTrackingProvider(widget.orderId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (track) {
          _updateMapMarkers(track);

          return ListView(
            children: [
              // ── Map section ──
              if (track.courierLatitude != null && track.courierLongitude != null) ...[
                SizedBox(
                  height: 300,
                  child: GoogleMap(
                    initialCameraPosition: _initialCamera ?? CameraPosition(
                      target: _courierPos ?? const LatLng(5.6037, -0.1870), // Accra default
                      zoom: 14,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _fitBounds();
                    },
                  ),
                ),
              ] else ...[
                Container(
                  height: 200,
                  color: colors.card,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delivery_dining, size: 64, color: colors.textSecondary),
                      const SizedBox(height: 12),
                      Text('Waiting for courier location...',
                          style: TextStyle(color: colors.textSecondary)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ── ETA card ──
              if (track.estimatedArrival != null)
                _EtaCard(eta: track.estimatedArrival!, colors: colors)
                    .animate().fadeIn(duration: 300.ms),

              // ── Driver info ──
              if (track.driverName != null || track.vehiclePlate != null) ...[
                const SizedBox(height: 12),
                _DriverInfoCard(track: track, colors: colors),
              ],

              // ── Timeline ──
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Order Timeline',
                    style: TextStyle(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              timeline.when(
                data: (events) => events.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No tracking events yet',
                            style: TextStyle(color: colors.textSecondary)),
                      )
                    : Column(
                        children: events.asMap().entries.map((entry) {
                          final i = entry.key;
                          final e = entry.value;
                          final isLast = i == events.length - 1;
                          return _TimelineTile(event: e, isLast: isLast, colors: colors);
                        }).toList(),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const SizedBox(),
              ),

              const SizedBox(height: 32),

              // ── Delivery address ──
              if (track.deliveryAddress != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.divider),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: colors.accent, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(track.deliveryAddress!,
                              style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  void _updateMapMarkers(OrderTracking track) {
    final courierLat = track.courierLatitude;
    final courierLng = track.courierLongitude;
    final delLat = track.deliveryLatitude;
    final delLng = track.deliveryLongitude;

    _courierPos = (courierLat != null && courierLng != null) ? LatLng(courierLat, courierLng) : null;
    _deliveryPos = (delLat != null && delLng != null) ? LatLng(delLat, delLng) : null;

    if (_courierPos != null) {
      _initialCamera ??= CameraPosition(target: _courierPos!, zoom: 14);
    }

    final markers = <Marker>{};
    if (_courierPos != null) {
      markers.add(Marker(
        markerId: const MarkerId('courier'),
        position: _courierPos!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Courier'),
        rotation: track.courierHeading ?? 0,
      ));
    }
    if (_deliveryPos != null) {
      markers.add(Marker(
        markerId: const MarkerId('delivery'),
        position: _deliveryPos!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Delivery Location'),
      ));
    }
    _markers = markers;

    // Draw a simple straight-line polyline (in production, would use routing API)
    if (_courierPos != null && _deliveryPos != null) {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: [_courierPos!, _deliveryPos!],
          color: Colors.blue,
          width: 4,
          patterns: [PatternItem.dash(10), PatternItem.gap(10)],
        ),
      };
    }
  }

  void _fitBounds() {
    if (_mapController == null) return;
    if (_courierPos != null && _deliveryPos != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          _courierPos!.latitude < _deliveryPos!.latitude ? _courierPos!.latitude : _deliveryPos!.latitude,
          _courierPos!.longitude < _deliveryPos!.longitude ? _courierPos!.longitude : _deliveryPos!.longitude,
        ),
        northeast: LatLng(
          _courierPos!.latitude > _deliveryPos!.latitude ? _courierPos!.latitude : _deliveryPos!.latitude,
          _courierPos!.longitude > _deliveryPos!.longitude ? _courierPos!.longitude : _deliveryPos!.longitude,
        ),
      );
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } else if (_courierPos != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_courierPos!, 15));
    }
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _EtaCard extends StatelessWidget {
  final DateTime eta;
  final AzamanColors colors;
  const _EtaCard({required this.eta, required this.colors});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = eta.difference(now);
    final isArrived = diff.isNegative;
    final mins = diff.inMinutes.abs();
    final hours = mins ~/ 60;
    final remainingMins = mins % 60;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.accent, colors.accent.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(isArrived ? Icons.check_circle : Icons.access_time,
              color: Colors.white, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArrived ? 'Arrived' : 'Estimated Arrival',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  isArrived
                      ? 'Delivered'
                      : hours > 0
                          ? '${hours}h ${remainingMins}m'
                          : '${remainingMins} min',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                ),
                Text(
                  '${eta.toLocal().hour.toString().padLeft(2, '0')}:${eta.toLocal().minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }
}

class _DriverInfoCard extends StatelessWidget {
  final OrderTracking track;
  final AzamanColors colors;
  const _DriverInfoCard({required this.track, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: colors.accent.withOpacity(0.15),
            child: Icon(Icons.person, color: colors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (track.driverName != null)
                  Text(track.driverName!,
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                if (track.vehiclePlate != null)
                  Text('Plate: ${track.vehiclePlate}',
                      style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                if (track.courierSpeedKmh != null)
                  Text('${track.courierSpeedKmh!.toStringAsFixed(0)} km/h',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (track.driverPhone != null)
            IconButton(
              icon: Icon(Icons.phone, color: colors.accent),
              onPressed: () {
                // In production: launch dialer
              },
            ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final TimelineEvent event;
  final bool isLast;
  final AzamanColors colors;

  const _TimelineTile({required this.event, required this.isLast, required this.colors});

  @override
  Widget build(BuildContext context) {
    final icon = _statusIcon(event.status);
    final color = _statusColor(event.status, colors);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline rail
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: colors.divider,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.status.replaceAll('_', ' '),
                        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                    if (event.note.isNotEmpty)
                      Text(event.note, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                    Text(_formatTime(event.timestamp),
                        style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
      case 'CONFIRMED':
        return Icons.receipt;
      case 'PREPARING':
        return Icons.restaurant;
      case 'DISPATCHED':
      case 'PICKED_UP':
        return Icons.local_shipping;
      case 'EN_ROUTE':
      case 'ON_THE_WAY':
        return Icons.delivery_dining;
      case 'NEARBY':
        return Icons.location_searching;
      case 'DELIVERED':
        return Icons.check_circle;
      default:
        return Icons.circle;
    }
  }

  Color _statusColor(String status, AzamanColors colors) {
    switch (status.toUpperCase()) {
      case 'DELIVERED':
        return colors.success;
      case 'EN_ROUTE':
      case 'ON_THE_WAY':
        return colors.accent;
      case 'PREPARING':
        return Colors.orange;
      default:
        return colors.textSecondary;
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.toLocal().day}/${dt.toLocal().month} ${dt.toLocal().hour.toString().padLeft(2, '0')}:${dt.toLocal().minute.toString().padLeft(2, '0')}';
  }
}

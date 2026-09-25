import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/marketplace/experiences/hotel/hotel_experience.dart';

void main() {
  test('parses room payload and formats rate', () {
    final room = HotelRoom.fromJson({
      'roomId': 'r1',
      'roomName': 'Ocean Suite',
      'floor': 4,
      'pricePerNight': '850',
      'currency': 'GHS',
      'capacity': 2,
      'amenities': ['Wi-Fi', 'Breakfast'],
    });
    expect(room.id, 'r1');
    expect(room.name, 'Ocean Suite');
    expect(room.formattedRate, 'GH₵850.00 / night');
    expect(room.capacity, 2);
  });

  testWidgets('room explorer exposes selectable room', (tester) async {
    HotelRoom? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HotelRoomExplorer(
      rooms: const [HotelRoom(id: 'r1', name: 'Ocean Suite', nightlyRate: 850, currency: 'GHS')],
      onRoomSelected: (room) => selected = room,
    ))));
    expect(find.text('Ocean Suite'), findsOneWidget);
    await tester.tap(find.text('Ocean Suite'));
    expect(selected?.id, 'r1');
  });
}

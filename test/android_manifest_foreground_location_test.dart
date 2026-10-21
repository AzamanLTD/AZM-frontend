import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// G3 — FOREGROUND-ONLY location: the Android manifest must declare the
/// location permissions and the location FOREGROUND SERVICE type the
/// geolocator foreground-notification stream requires on Android 14+.
/// Background location is deliberately NOT declared — that absence is the
/// product contract, so this test guards it too.

void main() {
  test('AndroidManifest declares foreground location permissions and no '
      'background location', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
      ),
      reason: 'Near You needs coarse location',
    );
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
      ),
      reason: 'Near You needs fine location',
    );
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
      ),
      reason: 'the foreground location stream requires the service perm',
    );
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />',
      ),
      reason: 'Android 14+ requires the typed foreground service perm',
    );

    // The product contract: background location is never requested.
    expect(
      manifest,
      isNot(contains('ACCESS_BACKGROUND_LOCATION')),
      reason: 'background location must never be declared',
    );
  });
}

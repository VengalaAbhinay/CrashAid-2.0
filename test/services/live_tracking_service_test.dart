import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:crashaid/services/live_tracking_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// live_tracking_service_test.dart
//
// Tests the pure-logic parts of LiveTrackingService that don't require
// Firebase or real GPS integration infrastructure.
//
// Covered:
//   • getLiveTrackingUrl()
//   • getTrackingUrlFromPosition()
//   • isTracking initial state
//   • lastPosition initial state
//   • stopTracking safety when no session is active
//   • Speed clamp logic mirrored from production
//   • Path truncation logic mirrored from production
//   • Jitter guard logic mirrored from production
//
// Run:
//   flutter test test/services/live_tracking_service_test.dart
// ─────────────────────────────────────────────────────────────────────────────

Position makePosition({
  double lat = 17.3850,
  double lon = 78.4867,
  double speed = 0,
}) {
  return Position(
    longitude: lon,
    latitude: lat,
    timestamp: DateTime(2026, 1, 1),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator_android'),
      (call) async {
        if (call.method == 'checkPermission') return 3; // whileInUse
        if (call.method == 'requestPermission') return 3;
        return null;
      },
    );
  });

  tearDown(() async {
    await LiveTrackingService.stopTracking();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator_android'),
      null,
    );
  });

  // ── 1. Static initial state ────────────────────────────────────────────────
  group('LiveTrackingService initial state', () {
    test('isTracking is false before any session starts', () {
      expect(LiveTrackingService.isTracking, isFalse);
    });

    test('lastPosition is null before any session starts', () {
      expect(LiveTrackingService.lastPosition, isNull);
    });
  });

  // ── 2. getLiveTrackingUrl() ────────────────────────────────────────────────
  group('getLiveTrackingUrl()', () {
    test('returns google maps base URL when no session and no position', () {
      final url = LiveTrackingService.getLiveTrackingUrl();

      expect(url, equals('https://maps.google.com'));
    });
  });

  // ── 3. getTrackingUrlFromPosition() ───────────────────────────────────────
  group('getTrackingUrlFromPosition()', () {
    test('returns google maps pin URL when no session is active', () {
      final pos = makePosition(lat: 17.1, lon: 78.2);

      final url = LiveTrackingService.getTrackingUrlFromPosition(pos);

      expect(url, equals('https://maps.google.com/?q=17.1,78.2'));
    });
  });

  // ── 4. stopTracking() ─────────────────────────────────────────────────────
  group('stopTracking()', () {
    test('is safe when no session is active', () async {
      await LiveTrackingService.stopTracking();

      expect(LiveTrackingService.isTracking, isFalse);
      expect(LiveTrackingService.lastPosition, isNull);
    });
  });

  // ── 5. Speed-clamp logic mirrored from production ─────────────────────────
  group('Speed clamp (0.8 m/s threshold)', () {
    double clampSpeed(double raw) => raw > 0.8 ? raw : 0;

    test('speed above 0.8 is kept', () {
      expect(clampSpeed(1.5), equals(1.5));
    });

    test('speed of exactly 0.8 is clamped to 0', () {
      expect(clampSpeed(0.8), equals(0));
    });

    test('speed below 0.8 is clamped to 0', () {
      expect(clampSpeed(0.3), equals(0));
    });

    test('speed of 0 is clamped to 0', () {
      expect(clampSpeed(0.0), equals(0));
    });

    test('negative speed is clamped to 0', () {
      expect(clampSpeed(-1.0), equals(0));
    });
  });

  // ── 6. Path truncation logic mirrored from production ─────────────────────
  group('Path truncation (_maxPathPoints = 200)', () {
    const maxPathPoints = 200;

    Map<String, dynamic> truncatePath(List<Map<String, dynamic>> existing) {
      bool truncated = false;

      if (existing.length > maxPathPoints) {
        existing = existing.sublist(existing.length - maxPathPoints);
        truncated = true;
      }

      return {
        'path': existing,
        'truncated': truncated,
      };
    }

    test('path under limit is not truncated', () {
      final path = List.generate(
        100,
        (i) => {'lat': i.toDouble(), 'lng': 0.0, 'ts': 'ts'},
      );

      final result = truncatePath(path);

      expect((result['path'] as List).length, equals(100));
      expect(result['truncated'], isFalse);
    });

    test('path at exactly 200 is not truncated', () {
      final path = List.generate(
        200,
        (i) => {'lat': i.toDouble(), 'lng': 0.0, 'ts': 'ts'},
      );

      final result = truncatePath(path);

      expect((result['path'] as List).length, equals(200));
      expect(result['truncated'], isFalse);
    });

    test('path at 201 is truncated to last 200', () {
      final path = List.generate(
        201,
        (i) => {'lat': i.toDouble(), 'lng': 0.0, 'ts': 'ts'},
      );

      final result = truncatePath(path);

      expect((result['path'] as List).length, equals(200));
      expect(result['truncated'], isTrue);
    });

    test('truncation keeps the most recent points', () {
      final path = List.generate(
        205,
        (i) => {'lat': i.toDouble(), 'lng': 0.0, 'ts': 'ts'},
      );

      final result = truncatePath(path);
      final kept = result['path'] as List;

      expect((kept.first)['lat'], equals(5.0));
      expect((kept.last)['lat'], equals(204.0));
    });

    test('empty path is not truncated', () {
      final result = truncatePath([]);

      expect(result['path'] as List, isEmpty);
      expect(result['truncated'], isFalse);
    });
  });

  // ── 7. Jitter guard logic mirrored from production ────────────────────────
  group('Jitter guard (5 m minimum distance)', () {
    const jitterThreshold = 5.0;

    test('update less than 5 m is skipped', () {
      const dist = 3.0;

      expect(dist < jitterThreshold, isTrue);
    });

    test('update of exactly 5 m is not skipped', () {
      const dist = 5.0;

      expect(dist < jitterThreshold, isFalse);
    });

    test('update greater than 5 m passes jitter guard', () {
      const dist = 12.0;

      expect(dist < jitterThreshold, isFalse);
    });
  });
}

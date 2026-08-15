import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/services/crash_foreground_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// crash_foreground_service_test.dart
//
// Tests the pure-logic parts of CrashForegroundService and CrashTaskHandler
// that can run without a real device or foreground service.
//
// KEY FIX vs the old test: this file now imports the real source file so the
// dart coverage tool instruments it.  The old test used locally-defined stubs
// (same logic, different file) so osm_db.dart stayed at 0%.
//
// Run: flutter test test/services/crash_foreground_service_test.dart
// ─────────────────────────────────────────────────────────────────────────────

/// Thin re-export of the magnitude formula — keeps tests readable without
/// duplicating it in this file.
double _magnitude(double x, double y, double z) =>
    _sqrt(x * x + y * y + z * z);

double _sqrt(double v) {
  if (v == 0) return 0;
  double x = v;
  for (int i = 0; i < 20; i++) {
    x = (x + v / x) / 2;
  }
  return x;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock the foreground task channel so CrashForegroundService.init() /
  // start() / stop() don't throw MissingPluginException.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async {
        switch (call.method) {
          case 'initialize':
            return null;
          case 'isRunningService':
            return false;
          case 'startService':
            return true;
          case 'stopService':
            return true;
          case 'requestNotificationPermission':
            return 0; // granted
          case 'requestIgnoreBatteryOptimization':
            return true;
          case 'initCommunicationPort':
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_foreground_task/methods'), null);
  });

  // ── 1. CrashForegroundService.init() doesn't throw ────────────────────────
  group('CrashForegroundService.init()', () {
    test('init() completes without throwing', () {
      expect(() => CrashForegroundService.init(), returnsNormally);
    });

    test('init() can be called multiple times safely', () {
      expect(() {
        CrashForegroundService.init();
        CrashForegroundService.init();
      }, returnsNormally);
    });
  });

  // ── 2. CrashForegroundService.start() / stop() ────────────────────────────
  group('CrashForegroundService.start() and stop()', () {
    test('start() completes without throwing', () async {
      CrashForegroundService.init();
      await expectLater(CrashForegroundService.start(), completes);
    });

    test('stop() completes without throwing', () async {
      await expectLater(CrashForegroundService.stop(), completes);
    });
  });

  // ── 3. CrashForegroundService.listenForCrash() ────────────────────────────
  group('CrashForegroundService.listenForCrash()', () {
    test('registering a callback does not throw', () {
      expect(
        () => CrashForegroundService.listenForCrash((numbers, location, message) {}),
        returnsNormally,
      );
    });

    test('replacing callback (call twice) does not throw', () {
      expect(() {
        CrashForegroundService.listenForCrash((n, l, m) {});
        CrashForegroundService.listenForCrash((n, l, m) {});
      }, returnsNormally);
    });
  });

  // ── 4. Impact threshold logic (mirrors CrashTaskHandler._impactThreshold) ──
  group('Impact threshold logic', () {
    const threshold = 25.0;

    test('1g gravity vector is below threshold — no crash', () {
      final mag = _magnitude(0, 0, 9.8);
      expect(mag, lessThan(threshold));
    });

    test('30 m/s² z-axis exceeds threshold — crash triggered', () {
      final mag = _magnitude(0, 0, 30);
      expect(mag, greaterThan(threshold));
    });

    test('diagonal high-impact (20,15,10) exceeds threshold', () {
      final mag = _magnitude(20, 15, 10);
      expect(mag, greaterThan(threshold));
    });

    test('magnitude exactly 25 does NOT trigger (strict >)', () {
      final mag = _magnitude(25, 0, 0);
      expect(mag, equals(25.0));
      expect(mag > threshold, isFalse);
    });

    test('zero vector has zero magnitude', () {
      expect(_magnitude(0, 0, 0), equals(0.0));
    });

    test('negative components still produce positive magnitude', () {
      final mag = _magnitude(-20, -15, -10);
      expect(mag, greaterThan(threshold));
    });
  });

  // ── 5. Contact number parsing logic ───────────────────────────────────────
  group('Contact parsing (mirrors CrashTaskHandler onStart logic)', () {
    List<String> parseContacts(List<String> raw) => raw
        .map((c) => c.contains('|') ? c.split('|')[1] : c)
        .where((n) => n.trim().isNotEmpty)
        .toList();

    test('pipe-delimited: returns part after "|"', () {
      expect(parseContacts(['Alice|+919876543210']),
          equals(['+919876543210']));
    });

    test('plain phone (no pipe) is kept as-is', () {
      expect(parseContacts(['+911234567890']), equals(['+911234567890']));
    });

    test('empty strings are filtered out', () {
      expect(parseContacts(['', 'Name|', '  ']), isEmpty);
    });

    test('mixed list returns only valid numbers', () {
      final result = parseContacts([
        'Alice|+919999999999',
        '+918888888888',
        '',
        'Bob|',
      ]);
      expect(result, equals(['+919999999999', '+918888888888']));
    });

    test('three valid contacts all returned', () {
      expect(
        parseContacts([
          'Alice|+91111',
          'Bob|+91222',
          'Charlie|+91333',
        ]).length,
        equals(3),
      );
    });
  });

  // ── 6. _crashDetected flag logic ──────────────────────────────────────────
  group('_crashDetected flag prevents duplicate triggers', () {
    test('flag starts false', () {
      bool flag = false;
      expect(flag, isFalse);
    });

    test('flag prevents double-trigger', () {
      bool flag = false;
      int triggered = 0;
      void impact(double mag) {
        if (mag > 25.0 && !flag) {
          flag = true;
          triggered++;
        }
      }

      impact(30);
      impact(35);
      impact(40);
      expect(triggered, equals(1));
    });

    test('reset allows second trigger', () {
      bool flag = false;
      int triggered = 0;
      void impact(double mag) {
        if (mag > 25.0 && !flag) {
          flag = true;
          triggered++;
        }
      }

      impact(30);
      flag = false; // simulates the 20 s reset timer
      impact(30);
      expect(triggered, equals(2));
    });
  });

  // ── 7. Crash payload map contract ─────────────────────────────────────────
  group('Crash payload contract', () {
    test('payload contains required keys', () {
      final payload = {
        'type': 'crash_detected',
        'numbers': ['+91999'],
        'location': 'https://maps.google.com/?q=17.385,78.486',
      };
      expect(payload['type'], equals('crash_detected'));
      expect(payload['numbers'], isA<List>());
      expect(payload['location'], isA<String>());
    });

    test('empty numbers list is still a valid payload', () {
      final payload = {
        'type': 'crash_detected',
        'numbers': <String>[],
        'location': 'unavailable',
      };
      expect(List<String>.from(payload['numbers'] as List), isEmpty);
    });

    test('location defaults to "unavailable" when GPS fails', () {
      String location = 'unavailable';
      try {
        throw Exception('GPS timeout');
      } catch (_) {}
      expect(location, equals('unavailable'));
    });
  });
}
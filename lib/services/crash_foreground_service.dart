import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'contacts_db.dart';
import 'crash_math.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(CrashTaskHandler());
}

class CrashTaskHandler extends TaskHandler {
  StreamSubscription? _sub;
  Timer? _cooldownTimer;
  bool _crashDetected = false;

  // ── Crash detection ────────────────────────────────────────────────────
  static const double _impactThreshold = 25.0;
  int _consecutiveHits = 0;
  static const int _requiredHits = 2;
  static const double _minSpeedMs = 5.0 / 3.6;

  static const double _fallThreshold = 18.0;
  bool _fallDetected = false;
  int _stillnessCount = 0;
  static const int _requiredStillnessSamples = 25; // ~5s at 5Hz


  int _shakeCount = 0;
  DateTime? _firstShakeTime;
  static const int _requiredShakes = 3;
  static const Duration _shakeWindow = Duration(seconds: 3);
  static const double _shakeThreshold = 20.0;

  // ── Low-pass filter state ──────────────────────────────────────────────
  double _gx = 0, _gy = 0, _gz = 9.8;
  static const double _alpha = 0.8;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _sub?.cancel();

    _sub = accelerometerEventStream().listen((event) async {
      // Update gravity estimate
      _gx = _alpha * _gx + (1 - _alpha) * event.x;
      _gy = _alpha * _gy + (1 - _alpha) * event.y;
      _gz = _alpha * _gz + (1 - _alpha) * event.z;

      final magnitude = linearMagnitude(event.x, event.y, event.z, _gx, _gy, _gz);

      // ── Crash detection ──────────────────────────────────────────────
      if (magnitude > _impactThreshold) {
        _consecutiveHits++;
      } else {
        _consecutiveHits = 0;
      }

      if (_consecutiveHits >= _requiredHits && !_crashDetected) {
        _crashDetected = true;
        _consecutiveHits = 0;
        _cooldownTimer?.cancel();

        Position? pos;
        try {
          pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
          ).timeout(const Duration(seconds: 3));
        } catch (_) {}

        if (pos != null && pos.speed < _minSpeedMs) {
          debugPrint('🚗 Crash spike ignored — speed too low');
          _crashDetected = false;
          return;
        }

        String location = 'unavailable';
        try {
          final highPos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(const Duration(seconds: 8));
          location = 'https://maps.google.com/?q=${highPos.latitude},${highPos.longitude}';
        } catch (_) {}

        final numbers = await ContactsDb.instance.readNumbers(null);

        FlutterForegroundTask.sendDataToMain({
          'type': 'crash_detected',
          'numbers': numbers,
          'location': location,
        });

        _cooldownTimer = Timer(const Duration(minutes: 3), () {
          _crashDetected = false;
          _consecutiveHits = 0;
        });
        return;
      }

      // ── Fall detection (Challenge 06) ────────────────────────────────
      // Track stillness — near-zero linear acceleration
      if (magnitude < 2.0) {
        _stillnessCount++;
      } else {
        _stillnessCount = 0;
      }

      if (magnitude > _fallThreshold &&
          magnitude < _impactThreshold &&
          !_fallDetected &&
          !_crashDetected) {
        _fallDetected = true;

        // Wait 5 seconds then check if person is still (lying still after fall)
        Timer(const Duration(seconds: 5), () async {
          if (_stillnessCount >= _requiredStillnessSamples) {
            debugPrint('🧓 Fall detected — person appears still');

            String location = 'unavailable';
            try {
              final pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
              ).timeout(const Duration(seconds: 8));
              location = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
            } catch (_) {}

            final numbers = await ContactsDb.instance.readNumbers(null);

            FlutterForegroundTask.sendDataToMain({
              'type': 'fall_detected',
              'numbers': numbers,
              'location': location,
            });
          }
          _fallDetected = false;
          _stillnessCount = 0;
        });
      }

      // ── Shake to SOS (Challenge 06) ──────────────────────────────────
      if (magnitude > _shakeThreshold) {
        final now = DateTime.now();

        if (_firstShakeTime == null) {
          _firstShakeTime = now;
          _shakeCount = 1;
        } else if (now.difference(_firstShakeTime!) <= _shakeWindow) {
          _shakeCount++;
          if (_shakeCount >= _requiredShakes && !_crashDetected && !_fallDetected) {
            debugPrint('📳 Shake SOS triggered — $_shakeCount shakes detected');
            _shakeCount = 0;
            _firstShakeTime = null;

            String location = 'unavailable';
            try {
              final pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
              ).timeout(const Duration(seconds: 8));
              location = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
            } catch (_) {}

            final numbers = await ContactsDb.instance.readNumbers(null);

            FlutterForegroundTask.sendDataToMain({
              'type': 'shake_sos',
              'numbers': numbers,
              'location': location,
            });
          }
        } else {
          // Window expired — reset
          _firstShakeTime = now;
          _shakeCount = 1;
        }
      }
    }, cancelOnError: false);
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _sub?.cancel();
    _sub = null;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }
}

typedef CrashEventListener = void Function(
  List<String> numbers,
  String location,
  String type,
);

class CrashForegroundService {
  // Multiple independent parts of the app (the main SOS flow,
  // DashcamService for crash-footage preservation, etc.) each need to
  // hear about crash events — so this keeps a list of listeners rather
  // than a single overwritable callback. Registering a new listener
  // never disturbs listeners already registered elsewhere.
  static final List<CrashEventListener> _listeners = [];
  static void Function(Object)? _dispatcher;

  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'crash_detection',
        channelName: 'Crash Detection',
        channelDescription: 'Monitoring for crashes in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start() async {
    await FlutterForegroundTask.requestNotificationPermission();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'CrashAid Active 🛡',
        notificationText: 'Crash & safety detection running',
        callback: startCallback,
      );
    }
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  /// Registers a listener for crash, fall, and shake SOS events from the
  /// background isolate. Can be called from multiple places — every
  /// registered listener is notified of every event; none of them
  /// replace each other.
  static void listenForCrash(CrashEventListener onEvent) {
    _listeners.add(onEvent);
    _ensureDispatcherRegistered();
  }

  /// Removes a previously registered listener (e.g. from a screen's
  /// dispose()). Pass the exact same function reference given to
  /// [listenForCrash].
  static void removeCrashListener(CrashEventListener onEvent) {
    _listeners.remove(onEvent);
  }

  static void _ensureDispatcherRegistered() {
    if (_dispatcher != null) return;
    _dispatcher = (data) {
      if (data is Map) {
        final type = data['type'] as String? ?? 'crash_detected';
        if (type == 'crash_detected' ||
            type == 'fall_detected' ||
            type == 'shake_sos') {
          final numbers = List<String>.from(data['numbers'] ?? []);
          final location = data['location'] as String? ?? 'unavailable';
          for (final listener in List<CrashEventListener>.from(_listeners)) {
            listener(numbers, location, type);
          }
        }
      }
    };
    FlutterForegroundTask.addTaskDataCallback(_dispatcher!);
  }
}

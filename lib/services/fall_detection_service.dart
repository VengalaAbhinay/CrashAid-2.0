import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';

/// FallDetectionService
/// Uses the same accelerometer pipeline as crash detection but with:
/// - Lower impact threshold (18 m/s² vs 25 m/s²)
/// - Stillness confirmation after impact (5 seconds)
/// - No speed gate (seniors may fall while stationary)
class FallDetectionService {
  static StreamSubscription? _sub;
  static Timer? _stillnessTimer;
  static bool _fallSuspected = false;
  static bool _isRunning = false;

  // Callback fired when fall is confirmed
  static void Function(String location)? onFallDetected;

  // Accelerometer low-pass filter state
  static double _gx = 0, _gy = 0, _gz = 9.8;
  static const double _alpha = 0.8;

  // Thresholds
  static const double _impactThreshold = 18.0; // lower than crash (25.0)
  static const double _stillnessThreshold = 2.5; // m/s² - person is still
  static int _stillnessFrames = 0;
  static const int _requiredStillnessFrames = 25; // ~5 seconds at 5Hz

  static Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    debugPrint('👴 FallDetection started');

    _sub = accelerometerEventStream().listen((event) async {
      // Low-pass filter to separate gravity
      _gx = _alpha * _gx + (1 - _alpha) * event.x;
      _gy = _alpha * _gy + (1 - _alpha) * event.y;
      _gz = _alpha * _gz + (1 - _alpha) * event.z;

      // Linear acceleration magnitude (gravity removed)
      final lx = event.x - _gx;
      final ly = event.y - _gy;
      final lz = event.z - _gz;
      final magnitude = sqrt(lx * lx + ly * ly + lz * lz);

      // Raw magnitude (with gravity) — used for stillness check
      final rawMag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final stillness = (rawMag - 9.8).abs(); // deviation from gravity

      if (!_fallSuspected) {
        // Phase 1: detect impact spike
        if (magnitude > _impactThreshold) {
          _fallSuspected = true;
          _stillnessFrames = 0;
          debugPrint('👴 Fall impact detected (mag=$magnitude) — waiting for stillness...');
        }
      } else {
        // Phase 2: confirm stillness after impact
        if (stillness < _stillnessThreshold) {
          _stillnessFrames++;
        } else {
          // Movement resumed — not a fall (person is moving again)
          if (magnitude > 8.0) {
            _fallSuspected = false;
            _stillnessFrames = 0;
          }
        }

        if (_stillnessFrames >= _requiredStillnessFrames) {
          _fallSuspected = false;
          _stillnessFrames = 0;
          await _onFallConfirmed();
        }
      }
    }, cancelOnError: false);
  }

  static Future<void> _onFallConfirmed() async {
    debugPrint('👴 FALL CONFIRMED — firing callback');
    String location = 'unavailable';
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));
      location = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    } catch (_) {}

    onFallDetected?.call(location);

    // 3-minute cooldown
    _stillnessTimer?.cancel();
    _fallSuspected = true; // block re-detection during cooldown
    _stillnessTimer = Timer(const Duration(minutes: 3), () {
      _fallSuspected = false;
    });
  }

  static Future<void> stop() async {
    _isRunning = false;
    _fallSuspected = false;
    _stillnessFrames = 0;
    await _sub?.cancel();
    _sub = null;
    _stillnessTimer?.cancel();
    _stillnessTimer = null;
    debugPrint('👴 FallDetection stopped');
  }

  static bool get isRunning => _isRunning;
}

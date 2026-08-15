import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// ShakeSOSService
/// Detects 3 rapid shakes within 2 seconds → triggers SOS
/// Designed for elderly users who can't easily tap buttons
class ShakeSOSService {
  static StreamSubscription? _sub;
  static bool _isRunning = false;
  static VoidCallback? onShakeDetected;

  // Shake detection config
  static const double _shakeThreshold = 20.0; // m/s² linear acceleration
  static const int _requiredShakes = 3;
  static const Duration _shakeWindow = Duration(seconds: 2);

  static int _shakeCount = 0;
  static DateTime? _firstShakeTime;
  static bool _inCooldown = false;

  static Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    debugPrint('👴 ShakeSOS started');

    double gx = 0, gy = 0, gz = 9.8;
    const double alpha = 0.8;

    _sub = accelerometerEventStream().listen((event) {
      // Low-pass gravity filter
      gx = alpha * gx + (1 - alpha) * event.x;
      gy = alpha * gy + (1 - alpha) * event.y;
      gz = alpha * gz + (1 - alpha) * event.z;

      final lx = event.x - gx;
      final ly = event.y - gy;
      final lz = event.z - gz;
      final magnitude = sqrt(lx * lx + ly * ly + lz * lz);

      if (_inCooldown) return;

      if (magnitude > _shakeThreshold) {
        final now = DateTime.now();

        if (_firstShakeTime == null) {
          _firstShakeTime = now;
          _shakeCount = 1;
          debugPrint('👴 Shake 1 detected');
        } else {
          final elapsed = now.difference(_firstShakeTime!);
          if (elapsed <= _shakeWindow) {
            _shakeCount++;
            debugPrint('👴 Shake $_shakeCount detected');

            if (_shakeCount >= _requiredShakes) {
              _shakeCount = 0;
              _firstShakeTime = null;
              _inCooldown = true;

              debugPrint('👴 SHAKE SOS TRIGGERED!');
              onShakeDetected?.call();

              // 30-second cooldown to prevent re-trigger
              Timer(const Duration(seconds: 30), () {
                _inCooldown = false;
              });
            }
          } else {
            // Window expired — reset
            _firstShakeTime = now;
            _shakeCount = 1;
          }
        }
      }
    }, cancelOnError: false);
  }

  static Future<void> stop() async {
    _isRunning = false;
    _shakeCount = 0;
    _firstShakeTime = null;
    _inCooldown = false;
    await _sub?.cancel();
    _sub = null;
    debugPrint('👴 ShakeSOS stopped');
  }

  static bool get isRunning => _isRunning;
}

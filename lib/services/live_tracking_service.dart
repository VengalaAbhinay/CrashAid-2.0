import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// LiveTrackingService
/// Writes GPS position to Firebase Realtime Database every 10 metres or 15s.
/// Stores full path history so the web viewer can render the breadcrumb trail
/// even after a session ends or the page is refreshed.
///
/// v2 changes:
///  • Writes `speed` (m/s) to Firebase so LiveTrackingMapScreen can display km/h
///  • Heartbeat also refreshes `speed`
class LiveTrackingService {
  static StreamSubscription<Position>? _positionStream;
  static Timer? _stopTimer;
  static Timer? _timeUpdateTimer;
  static Position? _lastPosition;
  static bool isTracking = false;
  static String? _sessionId;

  // Guards against concurrent startTracking calls (e.g. rapid UI taps).
  static bool _starting = false;

  // Max path points stored in Firebase (prevents unbounded growth).
  // 1000 points ≈ 60 KB — well within Firebase RTDB's 10 MB node limit.
  // At a new point every 10 m driving at 60 km/h that covers ~2.8 hours.
  static const int _maxPathPoints = 1000;

  // Expose last position read-only
  static Position? get lastPosition => _lastPosition;

  // ── START TRACKING ────────────────────────────────────────────────────────
  static Future<void> startTracking(
    String? username, {
    Position? seedPosition,
    Duration duration = const Duration(hours: 2),
  }) async {
    if (_starting) {
      debugPrint('⚠️ LiveTracking: startTracking already in progress — ignoring');
      return;
    }
    _starting = true;
    try {
      await _startTrackingInternal(
        username,
        seedPosition: seedPosition,
        duration: duration,
      );
    } finally {
      _starting = false;
    }
  }

  static Future<void> _startTrackingInternal(
    String? username, {
    Position? seedPosition,
    Duration duration = const Duration(hours: 2),
  }) async {
    if (isTracking) await stopTracking();

    // Request permission if not yet granted
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('🔴 LiveTracking: location permission not granted — aborting');
      return;
    }

    _lastPosition = null;
    isTracking = true;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final displayName =
        FirebaseAuth.instance.currentUser?.displayName?.trim();
    final resolvedName =
        (displayName != null && displayName.isNotEmpty)
            ? displayName
            : (username ?? 'CrashAid User');

    _sessionId = '${uid}_${DateTime.now().millisecondsSinceEpoch}';
    final db = FirebaseDatabase.instance.ref('live_tracking/$_sessionId');

    final now = DateTime.now();
    final expiresAt = now.add(duration);

    final List<Map<String, dynamic>> initialPath = [];
    if (seedPosition != null) {
      initialPath.add({
        'lat': seedPosition.latitude,
        'lng': seedPosition.longitude,
        'ts': now.toIso8601String(),
      });
    }

    try {
      await db.set({
        'username': resolvedName,
        'started_at': now.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'active': true,
        'lat': seedPosition?.latitude ?? 0,
        'lng': seedPosition?.longitude ?? 0,
        'accuracy': seedPosition?.accuracy ?? 0,
        // v2: persist speed so the map screen can show km/h; clamp GPS noise
        'speed': (seedPosition?.speed != null && seedPosition!.speed > 0.8)
            ? seedPosition.speed
            : 0,
        'updated_at': now.toIso8601String(),
        'path': initialPath.isEmpty ? [] : initialPath,
        'path_truncated': false,
      });
    } catch (e) {
      debugPrint('🔴 LiveTracking: failed to write session to Firebase — $e');
      isTracking = false;
      _sessionId = null;
      _lastPosition = null;
      return;
    }

    // Firebase write succeeded — safe to restore seed position
    _lastPosition = seedPosition;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (Position position) => _pushPosition(db, position),
      onError: (e) => debugPrint('🔴 LiveTracking stream error: $e'),
    );

    // Heartbeat: only updates root fields — does NOT append duplicate path points
    _timeUpdateTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_lastPosition != null) {
        db.update({
          'lat': _lastPosition!.latitude,
          'lng': _lastPosition!.longitude,
          'accuracy': _lastPosition!.accuracy,
          // v2: keep speed fresh on heartbeat; clamp GPS noise below 0.8 m/s
          'speed': (_lastPosition!.speed > 0.8) ? _lastPosition!.speed : 0,
          'updated_at': DateTime.now().toIso8601String(),
        }).catchError(
          (e) => debugPrint('🔴 LiveTracking: heartbeat update failed — $e'),
        );
      }
    });

    _stopTimer = Timer(duration, () => stopTracking());

    debugPrint(
        '✅ LiveTracking started — session: $_sessionId, expires: $expiresAt');
  }

  // ── PUSH POSITION ─────────────────────────────────────────────────────────
  static Future<void> _pushPosition(
      DatabaseReference db, Position position) async {

    // Manual jitter guard — skip updates < 5 m to handle platforms
    // that don't honour distanceFilter reliably.
    if (_lastPosition != null) {
      final dist = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (dist < 5) return;
    }

    _lastPosition = position;
    final now = DateTime.now();

    try {
      // Read current path
      final snap = await db.child('path').get();
      List<dynamic> existing = [];
      if (snap.value is List) {
        existing = List<dynamic>.from(snap.value as List);
      } else if (snap.value is Map) {
        // Firebase may deserialise sparse arrays as Maps with numeric keys
        existing = (snap.value as Map).values.toList();
      }

      existing.add({
        'lat': position.latitude,
        'lng': position.longitude,
        'ts': now.toIso8601String(),
      });

      bool truncated = false;
      if (existing.length > _maxPathPoints) {
        existing = existing.sublist(existing.length - _maxPathPoints);
        truncated = true;
      }

      // Single update call: path + root fields + optional truncation flag
      await db.update({
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        // v2: write speed; clamp below 0.8 m/s (~3 km/h) to hide GPS noise
        'speed': (position.speed > 0.8) ? position.speed : 0,
        'updated_at': now.toIso8601String(),
        'path': existing,
        if (truncated) 'path_truncated': true,
      });
    } catch (e) {
      debugPrint('🔴 LiveTracking: position update failed — $e');
    }
  }

  // ── STOP TRACKING ─────────────────────────────────────────────────────────
  static Future<void> stopTracking() async {
    _stopTimer?.cancel();
    _timeUpdateTimer?.cancel();
    await _positionStream?.cancel();
    _positionStream = null;
    _stopTimer = null;
    _timeUpdateTimer = null;
    isTracking = false;
    _lastPosition = null; // clear early

    final sessionToStop = _sessionId;
    _sessionId = null; // null before async call

    if (sessionToStop != null) {
      try {
        await FirebaseDatabase.instance
            .ref('live_tracking/$sessionToStop')
            .update({'active': false});
        debugPrint(
            '✅ LiveTracking stopped — session $sessionToStop marked inactive');
      } catch (e) {
        debugPrint('🔴 LiveTracking: failed to mark session inactive — $e');
      }
    }
  }

  // ── LIVE TRACKING URL ─────────────────────────────────────────────────────
  static String getLiveTrackingUrl() {
    if (_sessionId != null) {
      return 'https://crashaid-a1d3c.web.app/track?id=$_sessionId';
    }
    if (_lastPosition != null) {
      return 'https://maps.google.com/?q='
          '${_lastPosition!.latitude},${_lastPosition!.longitude}';
    }
    return 'https://maps.google.com';
  }

  /// Returns the live tracking URL for a given [position].
  /// If a session is active, returns the live session URL (position is already
  /// being streamed). Otherwise returns a static Google Maps pin for [position].
  static String getTrackingUrlFromPosition(Position position) {
    if (_sessionId != null) {
      return 'https://crashaid-a1d3c.web.app/track?id=$_sessionId';
    }
    return 'https://maps.google.com/?q='
        '${position.latitude},${position.longitude}';
  }
}
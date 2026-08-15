import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// SafeRouteSession
/// ────────────────────────────────────────────────────────────────────────
/// True two-device model for "Child Safety / Safe Route":
///
///   • PARENT device — draws the route + school point, creates a session,
///     receives a short join code, then MONITORS: it watches the CHILD's
///     live position (read from Firebase) and runs deviation/arrival
///     checks against the route it drew. It never reads its own GPS for
///     this feature.
///
///   • CHILD device — enters the join code and becomes a pure GPS sender.
///     It does not draw a route or evaluate anything locally; it only
///     pushes its own position to Firebase under that session.
///
/// Firebase shape: safe_route_sessions/{code}
/// {
///   parent_uid, created_at, expires_at, active, status,
///   route_points: [{lat,lng}, ...],
///   school: {lat, lng, radius},
///   child_joined, child_lat, child_lng, child_accuracy, child_speed,
///   child_updated_at, child_path: [{lat,lng,ts}, ...]
/// }
///
/// status: 'waiting' (created, child hasn't joined) → 'sharing' (child is
/// actively sending GPS) → 'ended' (either side stopped it).
class SafeRouteSession {
  // Avoids visually-ambiguous characters (0/O, 1/I/L) for codes read aloud
  // or typed in by hand.
  static const _codeChars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int _codeLength = 6;
  static const int _maxPathPoints = 500;

  static DatabaseReference _ref(String code) =>
      FirebaseDatabase.instance.ref('safe_route_sessions/$code');

  static String _generateCode() {
    final rnd = Random.secure();
    return List.generate(
      _codeLength,
      (_) => _codeChars[rnd.nextInt(_codeChars.length)],
    ).join();
  }

  // ── PARENT: CREATE SESSION ────────────────────────────────────────────
  /// Parent has already drawn the route on their own device. This writes
  /// it to Firebase under a fresh short join code and returns that code.
  /// Throws if a unique code couldn't be allocated after a few tries.
  static Future<String> createSession({
    required List<Map<String, double>> routePoints,
    required Map<String, double> school, // {lat, lng, radius}
    Duration validFor = const Duration(hours: 6),
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final now = DateTime.now();

    for (int attempt = 0; attempt < 6; attempt++) {
      final code = _generateCode();
      final ref = _ref(code);

      // A thrown error here (e.g. PERMISSION_DENIED from Firebase rules)
      // will not fix itself by retrying with a different code — surface
      // it immediately instead of masking it behind 6 silent retries.
      final existing = await ref.get();
      if (existing.exists) continue; // genuine code collision — retry

      try {
        await ref.set({
          'parent_uid': uid,
          'created_at': now.toIso8601String(),
          'expires_at': now.add(validFor).toIso8601String(),
          'active': true,
          'status': 'waiting',
          'route_points':
              routePoints.map((p) => {'lat': p['lat'], 'lng': p['lng']}).toList(),
          'school': school,
          'child_joined': false,
          'child_path': [],
        });
        debugPrint('✅ SafeRoute: session created — code $code');
        return code;
      } catch (e) {
        debugPrint('🔴 SafeRoute: failed to write session — $e');
        rethrow;
      }
    }
    throw Exception('Could not allocate a join code — please try again');
  }

  // ── PARENT: WATCH SESSION (route + live child position) ────────────────
  static Stream<DatabaseEvent> watchSession(String code) =>
      _ref(code).onValue;

  static Future<void> endSession(String code) async {
    try {
      await _ref(code).update({'active': false, 'status': 'ended'});
      debugPrint('✅ SafeRoute: session $code ended by parent');
    } catch (e) {
      debugPrint('🔴 SafeRoute: failed to end session — $e');
    }
  }

  static Future<void> markStatus(String code, String status) async {
    try {
      await _ref(code).update({'status': status});
    } catch (e) {
      debugPrint('🔴 SafeRoute: failed to update status — $e');
    }
  }

  // ── CHILD: VALIDATE + JOIN + STREAM GPS ─────────────────────────────────
  static StreamSubscription<Position>? _childStream;
  static Timer? _childHeartbeat;
  static bool _childSharing = false;
  static String? _childCode;

  static bool get isChildSharing => _childSharing;

  /// Checks a code is real and still active before attempting to join —
  /// lets the child screen show a clear error instead of silently failing.
  static Future<bool> codeExists(String code) async {
    try {
      final snap = await _ref(code).get();
      if (!snap.exists) return false;
      final map = Map<String, dynamic>.from(snap.value as Map);
      final expiresAt = DateTime.tryParse(map['expires_at'] as String? ?? '');
      if (expiresAt != null && expiresAt.isBefore(DateTime.now())) return false;
      return map['active'] == true;
    } catch (e) {
      debugPrint('🔴 SafeRoute: code lookup failed — $e');
      return false;
    }
  }

  /// Child becomes the GPS sender for [code]. Pushes position only —
  /// no route drawing, no deviation logic happens on this device.
  static Future<bool> joinAsChild(String code) async {
    if (_childSharing) await stopChildSharing();

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('🔴 SafeRoute(child): location permission not granted');
      return false;
    }

    final ref = _ref(code);
    try {
      final snap = await ref.get();
      if (!snap.exists) return false;

      await ref.update({'child_joined': true, 'status': 'sharing'});
    } catch (e) {
      debugPrint('🔴 SafeRoute(child): failed to join session — $e');
      return false;
    }

    _childSharing = true;
    _childCode = code;

    _childStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      (pos) => _pushChildPosition(ref, pos),
      onError: (e) => debugPrint('🔴 SafeRoute(child) stream error: $e'),
    );

    _childHeartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      ref
          .update({'child_updated_at': DateTime.now().toIso8601String()})
          .catchError((e) =>
              debugPrint('🔴 SafeRoute(child): heartbeat failed — $e'));
    });

    debugPrint('✅ SafeRoute(child): now sharing for session $code');
    return true;
  }

  static Future<void> _pushChildPosition(
      DatabaseReference ref, Position pos) async {
    final now = DateTime.now();
    try {
      final snap = await ref.child('child_path').get();
      List<dynamic> existing = [];
      if (snap.value is List) {
        existing = List<dynamic>.from(snap.value as List);
      } else if (snap.value is Map) {
        existing = (snap.value as Map).values.toList();
      }

      existing.add({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'ts': now.toIso8601String(),
      });
      if (existing.length > _maxPathPoints) {
        existing = existing.sublist(existing.length - _maxPathPoints);
      }

      await ref.update({
        'child_lat': pos.latitude,
        'child_lng': pos.longitude,
        'child_accuracy': pos.accuracy,
        'child_speed': (pos.speed > 0.8) ? pos.speed : 0,
        'child_updated_at': now.toIso8601String(),
        'child_path': existing,
      });
    } catch (e) {
      debugPrint('🔴 SafeRoute(child): position push failed — $e');
    }
  }

  /// Stops sharing. Safe to call even if nothing is active.
  static Future<void> stopChildSharing() async {
    _childHeartbeat?.cancel();
    await _childStream?.cancel();
    _childStream = null;
    _childHeartbeat = null;
    _childSharing = false;

    final code = _childCode;
    _childCode = null;
    if (code == null) return;

    try {
      await _ref(code).update({'status': 'ended'});
      debugPrint('✅ SafeRoute(child): stopped sharing for $code');
    } catch (e) {
      debugPrint('🔴 SafeRoute(child): failed to mark ended — $e');
    }
  }

  // ── GEOMETRY HELPERS (shared by the parent's monitor screen) ───────────
  /// Distance in metres from point P to line segment AB — used so a route
  /// drawn as connected waypoints is checked as a path, not just nearest
  /// dot, matching how a real road/footpath deviation should be judged.
  static double pointToSegmentDistanceMeters(
    double pLat,
    double pLng,
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    final lat2m = 111320.0;
    final lng2m = 111320.0 * cos(aLat * pi / 180);

    final px = (pLng - aLng) * lng2m;
    final py = (pLat - aLat) * lat2m;
    final dx = (bLng - aLng) * lng2m;
    final dy = (bLat - aLat) * lat2m;

    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return sqrt(px * px + py * py);

    final t = ((px * dx + py * dy) / lenSq).clamp(0.0, 1.0);
    final projX = t * dx - px;
    final projY = t * dy - py;
    return sqrt(projX * projX + projY * projY);
  }

  /// Minimum distance from [pLat],[pLng] to the full polyline described by
  /// [routePoints] (each a {'lat':..,'lng':..} map, in order).
  static double minDistanceToRouteMeters(
    double pLat,
    double pLng,
    List<Map<String, double>> routePoints,
  ) {
    if (routePoints.length < 2) {
      if (routePoints.isEmpty) return 0;
      return haversineMeters(
          pLat, pLng, routePoints.first['lat']!, routePoints.first['lng']!);
    }
    double minDist = double.infinity;
    for (int i = 0; i < routePoints.length - 1; i++) {
      final d = pointToSegmentDistanceMeters(
        pLat,
        pLng,
        routePoints[i]['lat']!,
        routePoints[i]['lng']!,
        routePoints[i + 1]['lat']!,
        routePoints[i + 1]['lng']!,
      );
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  static double haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
  }
}
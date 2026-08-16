import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'pothole_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// AmbulanceRoutingService
///
/// Implements the "Intelligent Ambulance Routing" checklist for CrashAid:
///   1. Emergency Mode          → see AmbulanceRoutingScreen (activation)
///   2. Live Ambulance/Patient GPS → see AmbulanceRoutingScreen (Geolocator
///                                   stream + LiveTrackingService)
///   3. Hospital Selection      → findNearbyHospitals + selectBestHospital
///   4. Route Calculation       → fetchRoutes
///   5. Traffic-Aware Routing   → pickBestRoute (duration + hazard penalty)
///   6. Dynamic Rerouting       → shouldReroute / hasDeviatedFromRoute
/// ─────────────────────────────────────────────────────────────────────────

/// A hospital candidate discovered near the crash/patient.
class HospitalCandidate {
  final String name;
  final LatLng location;
  final bool hasEmergencyDept; // OSM tag emergency=yes
  final bool isTraumaCenter; // OSM tag healthcare=hospital or name hints
  final String? phone;

  /// Straight-line distance from the patient — used only for pre-filtering
  /// candidates before the (expensive) routing calls.
  double straightLineMeters = 0;

  /// Filled in once selectBestHospital() has computed a real driving route.
  double? roadDistanceMeters;
  double? etaSeconds;

  /// Lower is better. Combines ETA + distance + suitability bonus.
  double? suitabilityCost;

  HospitalCandidate({
    required this.name,
    required this.location,
    this.hasEmergencyDept = false,
    this.isTraumaCenter = false,
    this.phone,
  });

  String get etaLabel {
    if (etaSeconds == null) return '—';
    final mins = (etaSeconds! / 60).round();
    return mins < 1 ? '<1 min' : '$mins min';
  }

  String get distanceLabel {
    final m = roadDistanceMeters ?? straightLineMeters;
    return m < 1000
        ? '${m.round()} m'
        : '${(m / 1000).toStringAsFixed(1)} km';
  }

  String get suitabilityLabel {
    final tags = <String>[];
    if (hasEmergencyDept) tags.add('Emergency dept.');
    if (isTraumaCenter) tags.add('Trauma-capable');
    return tags.isEmpty ? 'General hospital' : tags.join(' • ');
  }
}

/// One candidate driving route between two points.
class AmbulanceRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  /// Number of crowd-sourced hazards (potholes etc.) within the risk
  /// corridor of this route.
  int hazardCount = 0;

  /// Synthetic seconds added on top of [durationSeconds] to represent the
  /// risk/delay of hazards along the route — this is what lets the service
  /// prefer a slightly longer route that avoids a cluster of bad potholes.
  double hazardPenaltySeconds = 0;

  AmbulanceRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  /// "Effective" duration used to rank routes — lower is better.
  double get effectiveDurationSeconds => durationSeconds + hazardPenaltySeconds;

  String get etaLabel {
    final mins = (effectiveDurationSeconds / 60).round();
    return mins < 1 ? '<1 min' : '$mins min';
  }

  String get distanceLabel => distanceMeters < 1000
      ? '${distanceMeters.round()} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';
}

class AmbulanceRoutingService {
  AmbulanceRoutingService._();

  // Multiple public mirrors — the free Overpass/OSRM demo servers are
  // sometimes slow, rate-limited, or briefly down. Trying several in
  // sequence avoids a single flaky server making the whole feature look
  // "offline" when the device actually has a working connection.
  // Overpass mirrors reject or throttle requests that look like anonymous
  // bot traffic (no identifiable client). Sending a descriptive User-Agent
  // + Accept header is required by overpass-api.de's usage policy and
  // avoids the 406 seen on real devices.
  static const Map<String, String> _apiHeaders = {
    'User-Agent': 'CrashAidApp/1.0 (Flutter; Android; Road Safety Hackathon)',
    'Accept': 'application/json',
  };

  static const List<String> _overpassMirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.openstreetmap.fr/api/interpreter',
  ];

  static const List<String> _osrmMirrors = [
    'https://router.project-osrm.org/route/v1/driving',
    'https://routing.openstreetmap.de/routed-car/route/v1/driving',
  ];

  // How close (metres) a hazard has to be to the route line to count
  // against it.
  static const double _hazardCorridorMeters = 80;

  // Synthetic delay added per hazard, scaled by severity — represents the
  // real-world cost (slow-down / detour risk) of driving an ambulance over
  // or around a bad pothole at speed.
  static const Map<String, double> _hazardPenaltyBySeverity = {
    'Low': 8,
    'Medium': 25,
    'High': 60,
  };

  // How far (metres) the ambulance may drift from its planned route before
  // a fresh route is calculated.
  static const double _rerouteDeviationMeters = 90;

  // ── STEP 3: HOSPITAL SELECTION ────────────────────────────────────────

  /// Queries OpenStreetMap (via Overpass) for hospitals within [radiusM] of
  /// [origin]. Returns candidates sorted by straight-line distance —
  /// caller should narrow this down before requesting real routes.
  static Future<List<HospitalCandidate>> findNearbyHospitals(
    LatLng origin, {
    double radiusM = 15000,
  }) async {
    final query = '''
[out:json][timeout:15];
(
  node["amenity"="hospital"](around:$radiusM,${origin.latitude},${origin.longitude});
  way["amenity"="hospital"](around:$radiusM,${origin.latitude},${origin.longitude});
  relation["amenity"="hospital"](around:$radiusM,${origin.latitude},${origin.longitude});
);
out center tags;
''';

    try {
      http.Response? response;
      Object? lastError;

      for (final mirror in _overpassMirrors) {
        try {
          response = await http
              .post(
                Uri.parse(mirror),
                headers: {
                  ..._apiHeaders,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: {'data': query},
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) break;
          debugPrint('🟠 AmbulanceRoutingService: $mirror returned ${response.statusCode}');
          response = null;
        } catch (e) {
          lastError = e;
          debugPrint('🟠 AmbulanceRoutingService: $mirror failed — $e');
        }
      }

      if (response == null || response.statusCode != 200) {
        debugPrint('🔴 AmbulanceRoutingService: all Overpass mirrors failed — $lastError');
        return [];
      }

      final data = json.decode(response.body);
      final List elements = data['elements'] ?? [];

      final List<HospitalCandidate> hospitals = [];
      for (final e in elements) {
        final tags = (e['tags'] as Map?) ?? {};
        double? lat = e['lat']?.toDouble();
        double? lon = e['lon']?.toDouble();
        if (lat == null || lon == null) {
          final center = e['center'];
          if (center != null) {
            lat = (center['lat'] as num?)?.toDouble();
            lon = (center['lon'] as num?)?.toDouble();
          }
        }
        if (lat == null || lon == null) continue;

        final name = (tags['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;

        final emergency = (tags['emergency'] as String?)?.toLowerCase();
        final healthcare = (tags['healthcare'] as String?)?.toLowerCase();
        final nameLower = name.toLowerCase();

        final candidate = HospitalCandidate(
          name: name,
          location: LatLng(lat, lon),
          hasEmergencyDept: emergency == 'yes',
          isTraumaCenter: healthcare == 'hospital' ||
              nameLower.contains('trauma') ||
              nameLower.contains('multi') ||
              nameLower.contains('super speciality') ||
              nameLower.contains('superspeciality'),
          phone: tags['phone'] as String? ?? tags['contact:phone'] as String?,
        );
        candidate.straightLineMeters = _haversine(origin, candidate.location);
        hospitals.add(candidate);
      }

      hospitals.sort(
          (a, b) => a.straightLineMeters.compareTo(b.straightLineMeters));
      return hospitals;
    } catch (e) {
      debugPrint('🔴 AmbulanceRoutingService: findNearbyHospitals failed — $e');
      return [];
    }
  }

  /// Scores the [maxCandidates] nearest hospitals on real driving distance
  /// + ETA + clinical suitability (not just "nearest"), and returns them
  /// sorted best-first. The first element is the recommended hospital.
  ///
  /// Scoring intentionally weights ETA highest (0.5), since minutes matter
  /// most for a critical patient, then distance (0.35), then subtracts a
  /// small suitability bonus (0.15) for hospitals with an emergency
  /// department or trauma capability — so a slightly-further trauma
  /// center can beat a slightly-closer general clinic.
  static Future<List<HospitalCandidate>> selectBestHospital(
    List<HospitalCandidate> allHospitals,
    LatLng origin, {
    int maxCandidates = 5,
  }) async {
    if (allHospitals.isEmpty) return [];

    final candidates = allHospitals.take(maxCandidates).toList();

    // Fetch a real driving route to each candidate in parallel.
    await Future.wait(candidates.map((h) async {
      final routes = await fetchRoutes(origin, h.location, alternatives: false);
      if (routes.isNotEmpty) {
        h.roadDistanceMeters = routes.first.distanceMeters;
        h.etaSeconds = routes.first.durationSeconds;
      } else {
        // Routing failed (offline / OSRM unreachable) — fall back to a
        // rough estimate so the hospital can still be ranked.
        h.roadDistanceMeters = h.straightLineMeters * 1.3;
        h.etaSeconds = (h.straightLineMeters * 1.3) / (11.0); // ~40 km/h
      }
    }));

    final maxDist = candidates
        .map((h) => h.roadDistanceMeters ?? 0)
        .fold<double>(1, (a, b) => max(a, b));
    final maxTime = candidates
        .map((h) => h.etaSeconds ?? 0)
        .fold<double>(1, (a, b) => max(a, b));

    for (final h in candidates) {
      final normDist = (h.roadDistanceMeters ?? 0) / maxDist;
      final normTime = (h.etaSeconds ?? 0) / maxTime;
      double bonus = 0;
      if (h.hasEmergencyDept) bonus += 0.15;
      if (h.isTraumaCenter) bonus += 0.10;
      h.suitabilityCost = (normDist * 0.35) + (normTime * 0.50) - bonus;
    }

    candidates.sort((a, b) => a.suitabilityCost!.compareTo(b.suitabilityCost!));
    return candidates;
  }

  // ── STEP 4 & 5: ROUTE CALCULATION + TRAFFIC-AWARE SELECTION ───────────

  /// Requests one or more candidate driving routes from OSRM between
  /// [from] and [to]. Set [alternatives] to true to receive multiple
  /// route options so a traffic/hazard-aware choice can be made.
  static Future<List<AmbulanceRoute>> fetchRoutes(
    LatLng from,
    LatLng to, {
    bool alternatives = true,
  }) async {
    for (final base in _osrmMirrors) {
      final url = Uri.parse(
        '$base/${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson&alternatives=${alternatives ? 'true' : 'false'}&steps=false',
      );

      try {
        final response = await http
            .get(url, headers: _apiHeaders)
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          debugPrint('🟠 AmbulanceRoutingService: $base returned ${response.statusCode}');
          continue;
        }

        final data = json.decode(response.body);
        if (data['code'] != 'Ok') {
          debugPrint('🟠 AmbulanceRoutingService: $base responded ${data['code']}');
          continue;
        }

        final List routes = data['routes'] ?? [];
        return routes.map<AmbulanceRoute>((r) {
          final coords = (r['geometry']['coordinates'] as List)
              .map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          return AmbulanceRoute(
            points: coords,
            distanceMeters: (r['distance'] as num).toDouble(),
            durationSeconds: (r['duration'] as num).toDouble(),
          );
        }).toList();
      } catch (e) {
        debugPrint('🟠 AmbulanceRoutingService: $base failed — $e');
      }
    }

    debugPrint('🔴 AmbulanceRoutingService: all OSRM mirrors failed');
    return [];
  }

  /// Traffic-aware + hazard-aware route selection.
  ///
  /// OSRM's `duration` already reflects road class/speed limits (the
  /// closest free proxy for "traffic-aware" without a paid live-traffic
  /// API), so picking the lowest OSRM duration favours the *fastest* road,
  /// not simply the shortest one. On top of that, each route is penalised
  /// for crowd-sourced hazards (potholes) that fall inside its risk
  /// corridor, so a route through a cluster of bad potholes can lose out
  /// to a slightly slower but safer alternative — i.e. "avoid blocked or
  /// high-risk roads where possible".
  static AmbulanceRoute pickBestRoute(
    List<AmbulanceRoute> candidates,
    List<PotholeReport> hazards,
  ) {
    for (final route in candidates) {
      final nearby = hazards.where(
        (h) => _minDistanceToRoute(LatLng(h.lat, h.lng), route.points) <=
            _hazardCorridorMeters,
      );
      route.hazardCount = nearby.length;
      route.hazardPenaltySeconds = nearby.fold<double>(
        0,
        (sum, h) => sum + (_hazardPenaltyBySeverity[h.severity] ?? 20),
      );
    }

    candidates.sort(
        (a, b) => a.effectiveDurationSeconds.compareTo(b.effectiveDurationSeconds));
    return candidates.first;
  }

  // ── STEP 6: DYNAMIC REROUTING ──────────────────────────────────────────

  /// True once the ambulance/patient has drifted more than the reroute
  /// threshold away from the currently displayed route (e.g. a manual
  /// detour, a closed road) — signals the caller to recompute.
  static bool hasDeviatedFromRoute(LatLng current, AmbulanceRoute route) {
    if (route.points.length < 2) return false;
    return _minDistanceToRoute(current, route.points) > _rerouteDeviationMeters;
  }

  // ── GEOMETRY HELPERS ────────────────────────────────────────────────────

  static double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final la1 = a.latitude * pi / 180;
    final la2 = b.latitude * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(la1) * cos(la2) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * atan2(sqrt(h), sqrt(1 - h));
  }

  static double _pointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    final lat2m = 111320.0;
    final lng2m = 111320.0 * cos(a.latitude * pi / 180);

    final px = (p.longitude - a.longitude) * lng2m;
    final py = (p.latitude - a.latitude) * lat2m;
    final dx = (b.longitude - a.longitude) * lng2m;
    final dy = (b.latitude - a.latitude) * lat2m;

    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return sqrt(px * px + py * py);

    final t = ((px * dx + py * dy) / lenSq).clamp(0.0, 1.0);
    final projX = t * dx - px;
    final projY = t * dy - py;
    return sqrt(projX * projX + projY * projY);
  }

  /// Sample-based min distance from [p] to the polyline [route] — routes
  /// from OSRM can have hundreds of points, so for hazard/deviation checks
  /// we only need "close enough", not a full projection over every segment.
  static double _minDistanceToRoute(LatLng p, List<LatLng> route) {
    if (route.isEmpty) return double.infinity;
    if (route.length == 1) return _haversine(p, route.first);

    double minDist = double.infinity;
    // Step through in chunks for very long routes to keep this cheap.
    final step = route.length > 400 ? (route.length / 400).ceil() : 1;
    for (int i = 0; i < route.length - 1; i += step) {
      final d = _pointToSegmentMeters(p, route[i], route[i + 1]);
      if (d < minDist) minDist = d;
      if (minDist < 5) break; // close enough, stop early
    }
    return minDist;
  }
}

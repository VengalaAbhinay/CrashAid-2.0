import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ambulance_routing_service.dart';
import '../services/live_tracking_service.dart';
import '../services/pothole_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// AmbulanceRoutingScreen — "Intelligent Ambulance Routing" (Road Safety)
///
/// 1. Emergency Mode        — activates as soon as this screen opens
///                             (from a confirmed crash or manually).
/// 2. Live Ambulance/Patient GPS — a live Geolocator stream drives the map
///                             marker, and LiveTrackingService mirrors the
///                             same position to Firebase so it can be
///                             watched remotely (dispatcher/contacts).
/// 3. Hospital Selection    — nearby hospitals are scored on distance +
///                             ETA + suitability, not just nearest.
/// 4. Route Calculation     — a real driving route (OSRM) is drawn from the
///                             live position to the selected hospital.
/// 5. Traffic-Aware Routing — the fastest OSRM alternative is chosen, and
///                             routes through hazard clusters are penalised.
/// 6. Dynamic Rerouting     — the route is recalculated on a timer and
///                             whenever the live position drifts off it.
/// ─────────────────────────────────────────────────────────────────────────
class AmbulanceRoutingScreen extends StatefulWidget {
  /// Optional seed location (e.g. the crash GPS fix). If omitted, the
  /// screen fetches the current device location on open.
  final double? initialLat;
  final double? initialLng;

  const AmbulanceRoutingScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<AmbulanceRoutingScreen> createState() => _AmbulanceRoutingScreenState();
}

class _AmbulanceRoutingScreenState extends State<AmbulanceRoutingScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF0A0A0F);
  static const _red = Color(0xFFFF3B3B);
  static const _blue = Color(0xFF3B6FFF);
  static const _green = Color(0xFF00C851);
  static const _amber = Color(0xFFFFB300);

  final MapController _mapController = MapController();
  late final AnimationController _pulseController;
  StreamSubscription<Position>? _positionStream;
  Timer? _rerouteTimer;
  StreamSubscription<List<PotholeReport>>? _hazardSub;

  bool _emergencyModeActive = true;
  bool _loading = true;
  bool _isOffline = false;
  String _statusMessage = 'Getting your location…';

  LatLng? _currentPosition;
  List<HospitalCandidate> _hospitals = [];
  HospitalCandidate? _selectedHospital;
  AmbulanceRoute? _activeRoute;
  List<PotholeReport> _hazards = [];

  int _rerouteCount = 0;
  bool _recalculating = false;
  DateTime? _lastRouteAt;

  /// Checks actual internet connectivity (not just whether one Overpass/OSRM
  /// mirror responded) so the UI can tell "you're really offline" apart
  /// from "the free routing servers are being flaky right now".
  Future<bool> _hasRealInternet() async {
    try {
      final result = await InternetAddress.lookup('openstreetmap.org')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
          ..repeat();
    _hazardSub = PotholeService.watchAll().listen((reports) {
      _hazards = reports;
      // Condition change → re-evaluate whether the current route is still
      // the safest one (dynamic rerouting triggered by new hazard data).
      if (_activeRoute != null && !_recalculating) {
        final onRouteNow = _hazards.where((h) => AmbulanceRoutingService
                .hasDeviatedFromRoute(LatLng(h.lat, h.lng), _activeRoute!) ==
            false);
        if (onRouteNow.length != _activeRoute!.hazardCount) {
          _recalculateRoute(reason: 'New hazard reported nearby');
        }
      }
    }, onError: (_) {});
    _bootstrap();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _positionStream?.cancel();
    _rerouteTimer?.cancel();
    _hazardSub?.cancel();
    // Emergency Mode ends when this screen closes.
    LiveTrackingService.stopTracking();
    super.dispose();
  }

  // ── BOOTSTRAP: EMERGENCY MODE ACTIVATION ───────────────────────────────
  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _isOffline = false;
      _statusMessage = 'Getting your location…';
    });

    Position? seed;
    try {
      if (widget.initialLat != null && widget.initialLng != null) {
        _currentPosition = LatLng(widget.initialLat!, widget.initialLng!);
      } else {
        seed = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 10));
        _currentPosition = LatLng(seed.latitude, seed.longitude);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _statusMessage = 'Could not get your location. Check GPS & permissions.';
      });
      return;
    }

    // Live Ambulance/Patient GPS — mirror to Firebase so dispatch/contacts
    // can watch this session too, and start a local stream for the map.
    unawaited(LiveTrackingService.startTracking(
      'Ambulance / Patient',
      seedPosition: seed,
      duration: const Duration(hours: 3),
    ));
    _startLiveLocationStream();

    setState(() => _statusMessage = 'Finding nearby hospitals…');

    final all = await AmbulanceRoutingService.findNearbyHospitals(_currentPosition!);
    if (!mounted) return;

    if (all.isEmpty) {
      final online = await _hasRealInternet();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isOffline = true;
        _statusMessage = online
            ? 'Hospital directory is temporarily unavailable — the free map servers may be busy. Tap Retry.'
            : "You're offline — check your connection and tap Retry.";
      });
      return;
    }

    setState(() => _statusMessage = 'Choosing the best hospital…');

    final ranked =
        await AmbulanceRoutingService.selectBestHospital(all, _currentPosition!);
    if (!mounted) return;

    setState(() {
      _hospitals = ranked;
      _selectedHospital = ranked.isNotEmpty ? ranked.first : null;
    });

    await _calculateRouteToSelected();

    if (!mounted) return;
    setState(() => _loading = false);

    // Dynamic rerouting — periodic recompute so traffic/hazard conditions
    // are re-checked even if the ambulance hasn't visibly deviated.
    _rerouteTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _recalculateRoute(reason: 'Routine route refresh');
    });
  }

  void _startLiveLocationStream() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _currentPosition = LatLng(pos.latitude, pos.longitude));

      // Dynamic rerouting — recalc immediately if we've drifted off route.
      if (_activeRoute != null &&
          !_recalculating &&
          AmbulanceRoutingService.hasDeviatedFromRoute(
              _currentPosition!, _activeRoute!)) {
        _recalculateRoute(reason: 'Off planned route');
      }
    }, onError: (_) {});
  }

  // ── STEP 4 & 5: ROUTE CALCULATION + TRAFFIC-AWARE SELECTION ────────────
  Future<void> _calculateRouteToSelected() async {
    if (_currentPosition == null || _selectedHospital == null) return;

    final alternatives = await AmbulanceRoutingService.fetchRoutes(
      _currentPosition!,
      _selectedHospital!.location,
      alternatives: true,
    );

    if (alternatives.isEmpty) {
      final online = await _hasRealInternet();
      if (!mounted) return;
      setState(() {
        _isOffline = true;
        _statusMessage = online
            ? 'Route servers are temporarily unavailable. Tap Retry.'
            : "You're offline — check your connection and tap Retry.";
      });
      return;
    }

    final best = AmbulanceRoutingService.pickBestRoute(alternatives, _hazards);
    if (!mounted) return;
    setState(() {
      _activeRoute = best;
      _isOffline = false;
      _lastRouteAt = DateTime.now();
    });
  }

  Future<void> _recalculateRoute({required String reason}) async {
    if (_recalculating || _currentPosition == null || _selectedHospital == null) {
      return;
    }
    _recalculating = true;
    debugPrint('🔄 AmbulanceRouting: recalculating — $reason');
    await _calculateRouteToSelected();
    if (mounted) setState(() => _rerouteCount++);
    _recalculating = false;
  }

  Future<void> _selectHospital(HospitalCandidate hospital) async {
    setState(() {
      _selectedHospital = hospital;
      _activeRoute = null;
      _loading = true;
      _statusMessage = 'Calculating route…';
    });
    await _calculateRouteToSelected();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  // ── ACTIONS ──────────────────────────────────────────────────────────
  Future<void> _callAmbulance() async {
    final uri = Uri(scheme: 'tel', path: '108');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openInMaps() async {
    final h = _selectedHospital;
    if (h == null) return;
    final dest = '${h.location.latitude},${h.location.longitude}';
    final label = Uri.encodeComponent(h.name);
    final geoUri = Uri.parse('geo:$dest?q=$dest($label)');
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
      return;
    }
    final webUri =
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dest');
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  void _endEmergencyMode() {
    setState(() => _emergencyModeActive = false);
    Navigator.of(context).pop();
  }

  void _showHospitalPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF15151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Switch hospital',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Ranked by ETA, distance & suitability',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _hospitals.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (_, i) {
                      final h = _hospitals[i];
                      final isSelected = h == _selectedHospital;
                      return ListTile(
                        onTap: () {
                          Navigator.pop(ctx);
                          if (!isSelected) _selectHospital(h);
                        },
                        leading: Icon(Icons.local_hospital_rounded,
                            color: isSelected ? _green : _red),
                        title: Text(h.name,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${h.distanceLabel} • ${h.etaLabel} • ${h.suitabilityLabel}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: i == 0
                            ? const _Chip(label: 'BEST', color: _green)
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Ambulance Routing',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_emergencyModeActive)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _Chip(label: 'EMERGENCY', color: _red)),
            ),
        ],
      ),
      body: _loading
          ? _loadingView()
          : _currentPosition == null
              ? _errorView()
              : Column(
                  children: [
                    if (_isOffline) _offlineBanner(),
                    Expanded(flex: 6, child: _mapView()),
                    Expanded(flex: 5, child: _infoPanel()),
                  ],
                ),
    );
  }

  Widget _loadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _red),
          const SizedBox(height: 16),
          Text(_statusMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_rounded, color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            Text(_statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _bootstrap,
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _offlineBanner() {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _loading ? null : _bootstrap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
            ),
            child: const Text('Retry',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _mapView() {
    final hazardMarkers = _activeRoute == null
        ? <PotholeReport>[]
        : _hazards
            .where((h) => AmbulanceRoutingService.hasDeviatedFromRoute(
                    LatLng(h.lat, h.lng), _activeRoute!) ==
                false)
            .toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPosition!,
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.crashaid',
          errorTileCallback: (_, __, ___) {},
          keepBuffer: 5,
        ),
        if (_activeRoute != null)
          PolylineLayer(polylines: [
            Polyline(
              points: _activeRoute!.points,
              strokeWidth: 5,
              color: _activeRoute!.hazardCount > 0 ? _amber : _blue,
            ),
          ]),
        MarkerLayer(markers: [
          // Hazards on the active route.
          ...hazardMarkers.map((h) => Marker(
                point: LatLng(h.lat, h.lng),
                width: 30,
                height: 30,
                child: const Icon(Icons.warning_rounded, color: _amber, size: 22),
              )),

          // Other candidate hospitals (tap to switch).
          ..._hospitals.where((h) => h != _selectedHospital).map(
                (h) => Marker(
                  point: h.location,
                  width: 60,
                  height: 60,
                  child: GestureDetector(
                    onTap: () => _selectHospital(h),
                    child: const Icon(Icons.local_hospital_rounded,
                        color: Colors.white38, size: 28),
                  ),
                ),
              ),

          // Selected ("best") hospital.
          if (_selectedHospital != null)
            Marker(
              point: _selectedHospital!.location,
              width: 70,
              height: 70,
              child:
                  const Icon(Icons.local_hospital_rounded, color: _green, size: 40),
            ),

          // Live ambulance/patient position — pulsing marker.
          Marker(
            point: _currentPosition!,
            width: 70,
            height: 70,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final scale = 1.0 + _pulseController.value * 0.4;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _red.withValues(alpha: 1 - _pulseController.value),
                        ),
                      ),
                    ),
                    const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 28),
                  ],
                );
              },
            ),
          ),
        ]),
      ],
    );
  }

  Widget _infoPanel() {
    final h = _selectedHospital;
    final r = _activeRoute;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF14141C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_hospital_rounded, color: _green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    h?.name ?? 'No hospital selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const _Chip(label: 'BEST MATCH', color: _green),
              ],
            ),
            const SizedBox(height: 4),
            if (h != null)
              Text(h.suitabilityLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 14),
            Row(
              children: [
                _StatTile(
                    icon: Icons.route_rounded,
                    label: 'Distance',
                    value: r?.distanceLabel ?? h?.distanceLabel ?? '—'),
                const SizedBox(width: 10),
                _StatTile(
                    icon: Icons.timer_rounded,
                    label: 'ETA',
                    value: r?.etaLabel ?? h?.etaLabel ?? '—'),
                const SizedBox(width: 10),
                _StatTile(
                  icon: Icons.warning_amber_rounded,
                  label: 'Hazards on route',
                  value: '${r?.hazardCount ?? 0}',
                  highlight: (r?.hazardCount ?? 0) > 0,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _recalculating ? Icons.sync_rounded : Icons.check_circle_rounded,
                  color: _recalculating ? _amber : _green,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _recalculating
                        ? 'Recalculating route…'
                        : _lastRouteAt == null
                            ? 'Route not yet calculated'
                            : 'Traffic-aware route • rerouted $_rerouteCount time${_rerouteCount == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _callAmbulance,
                    icon: const Icon(Icons.call, color: Colors.white, size: 18),
                    label: const Text('Call 108',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: h == null ? null : _openInMaps,
                    icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
                    label: const Text('Navigate',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _hospitals.length < 2 ? null : _showHospitalPicker,
                    icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white70, size: 18),
                    label: const Text('Switch hospital',
                        style: TextStyle(color: Colors.white70)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _endEmergencyMode,
                    icon: const Icon(Icons.stop_circle_rounded, color: _red, size: 18),
                    label: const Text('End', style: TextStyle(color: _red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight ? const Color(0xFFFFB300) : Colors.white;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

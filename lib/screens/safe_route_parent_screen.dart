import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/contacts_db.dart';
import '../services/safe_route_service.dart';

enum _Stage { drawing, routeReady, creating, waitingChild, monitoring, ended }

class SafeRouteParentScreen extends StatefulWidget {
  final VoidCallback? onSosTap;
  const SafeRouteParentScreen({super.key, this.onSosTap});

  @override
  State<SafeRouteParentScreen> createState() => _SafeRouteParentScreenState();
}

class _SafeRouteParentScreenState extends State<SafeRouteParentScreen> {
  static const _smsChannel = MethodChannel('com.crashaid/sms');
  static const double _deviationThresholdMetres = 300.0;

  final MapController _mapController = MapController();
  final List<LatLng> _routePoints = [];
  LatLng? _parentPosition; // only used to centre the map while drawing
  LatLng? _childPosition; // live position reported by the CHILD device
  bool _isSettingRoute = false;

  _Stage _stage = _Stage.drawing;
  String _status = 'Tap on map to draw the safe route';
  String? _code;
  bool _childJoined = false;
  bool _deviationAlertSent = false;
  DateTime? _childUpdatedAt;

  StreamSubscription<DatabaseEvent>? _sessionSub;

  @override
  void initState() {
    super.initState();
    _getParentLocation();
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    if (_code != null) SafeRouteSession.endSession(_code!);
    super.dispose();
  }

  Future<void> _getParentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() => _parentPosition = LatLng(pos.latitude, pos.longitude));
        _mapController.move(_parentPosition!, 15);
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  // ── DRAW ROUTE ───────────────────────────────────────────────────────
  void _onMapTap(TapPosition tap, LatLng point) {
    if (!_isSettingRoute) return;
    setState(() {
      _routePoints.add(point);
      _status = _routePoints.length == 1
          ? 'Start set. Tap to add more waypoints.\nLast point = school/destination.'
          : '${_routePoints.length} points. Tap "Done" when route is complete.';
    });
  }

  void _startRouteSetup() {
    setState(() {
      _isSettingRoute = true;
      _routePoints.clear();
      _stage = _Stage.drawing;
      _status = 'Tap on map to mark the safe route (start → school)';
    });
  }

  void _finishRouteSetup() {
    if (_routePoints.length < 2) {
      _snack('Add at least 2 points to define a route', Colors.orange);
      return;
    }
    setState(() {
      _isSettingRoute = false;
      _stage = _Stage.routeReady;
      _status = 'Route set! Create a session to get a code for your child\'s phone.';
    });
  }

  // ── CREATE SESSION (this device = parent / monitor) ────────────────────
  Future<void> _createSession() async {
    setState(() {
      _stage = _Stage.creating;
      _status = 'Creating session…';
    });

    try {
      final school = _routePoints.last;
      final code = await SafeRouteSession.createSession(
        routePoints: _routePoints
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        school: {
          'lat': school.latitude,
          'lng': school.longitude,
          'radius': 150.0,
        },
      );

      setState(() {
        _code = code;
        _stage = _Stage.waitingChild;
        _status = 'Share this code with your child\'s phone';
      });

      _listenToSession(code);

      // Best-effort: also SMS the code to saved contacts so the child
      // doesn't have to be read it out loud.
      final numbers = await ContactsDb.instance.readNumbers(null);
      if (numbers.isNotEmpty) {
        await _smsChannel.invokeMethod('sendSMS', {
          'numbers': numbers,
          'message':
              '👦 Safe Route — join code: $code\nOpen CrashAid → Child Safety → "I\'m the Child" and enter this code to share your live location.',
        });
      }
    } catch (e) {
      setState(() {
        _stage = _Stage.routeReady;
        _status = 'Failed to create session: $e';
      });
    }
  }

  // ── MONITOR: listen to the CHILD's Firebase position ───────────────────
  void _listenToSession(String code) {
    _sessionSub = SafeRouteSession.watchSession(code).listen((event) {
      final data = event.snapshot.value;
      if (!mounted || data == null) return;
      final map = Map<String, dynamic>.from(data as Map);

      final joined = map['child_joined'] == true;
      final active = map['active'] == true;
      final status = map['status'] as String? ?? 'waiting';

      if (!active) {
        setState(() {
          _stage = _Stage.ended;
          _status = 'Session ended';
        });
        return;
      }

      final lat = (map['child_lat'] as num?)?.toDouble();
      final lng = (map['child_lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _childPosition = LatLng(lat, lng);
        if (map['child_updated_at'] != null) {
          _childUpdatedAt = DateTime.tryParse(map['child_updated_at'] as String);
        }
        _checkDeviation(lat, lng);
        _checkSchoolArrival(lat, lng);
      }

      setState(() {
        _childJoined = joined;
        if (joined && _stage == _Stage.waitingChild) {
          _stage = _Stage.monitoring;
        }
        if (status == 'sharing' && _childPosition != null) {
          _status = 'Monitoring — child is sharing live location';
        } else if (joined) {
          _status = 'Child connected — waiting for GPS fix…';
        }
      });

      if (_childPosition != null && _stage == _Stage.monitoring) {
        _mapController.move(
          _childPosition!,
          _mapController.camera.zoom < 15 ? 16 : _mapController.camera.zoom,
        );
      }
    }, onError: (e) {
      debugPrint('🔴 SafeRouteParent: session listen error — $e');
    });
  }

  void _checkDeviation(double lat, double lng) async {
    if (_deviationAlertSent) return;

    final routeMaps = _routePoints
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();
    final minDist =
        SafeRouteSession.minDistanceToRouteMeters(lat, lng, routeMaps);

    if (minDist > _deviationThresholdMetres) {
      _deviationAlertSent = true;
      setState(() =>
          _status = '⚠️ DEVIATION DETECTED — ${minDist.toInt()}m off route!');

      final numbers = await ContactsDb.instance.readNumbers(null);
      if (numbers.isNotEmpty) {
        final mapLink = 'https://maps.google.com/?q=$lat,$lng';
        await _smsChannel.invokeMethod('sendSMS', {
          'numbers': numbers,
          'message':
              '⚠️ ROUTE DEVIATION ALERT\nYour child has moved ${minDist.toInt()}m off the safe route!\nCurrent location: $mapLink',
        });
      }

      Future.delayed(const Duration(minutes: 5), () {
        if (mounted) _deviationAlertSent = false;
      });
    }
  }

  void _checkSchoolArrival(double lat, double lng) async {
    if (_routePoints.isEmpty) return;
    final school = _routePoints.last;
    final dist =
        SafeRouteSession.haversineMeters(lat, lng, school.latitude, school.longitude);

    if (dist <= 150.0) {
      setState(() => _status = '✅ Arrived at destination!');
      await _stopMonitoring();

      final numbers = await ContactsDb.instance.readNumbers(null);
      if (numbers.isNotEmpty) {
        await _smsChannel.invokeMethod('sendSMS', {
          'numbers': numbers,
          'message':
              '✅ ARRIVED SAFE\nYour child has reached their destination safely. Safe Route monitoring has ended.',
        });
      }
      if (mounted) {
        _snack('✅ Child arrived at destination!', const Color(0xFF00C851));
      }
    }
  }

  Future<void> _stopMonitoring() async {
    _sessionSub?.cancel();
    _sessionSub = null;
    if (_code != null) await SafeRouteSession.endSession(_code!);
    if (mounted) {
      setState(() {
        _stage = _Stage.ended;
        _status = 'Monitoring stopped';
      });
    }
  }

  void _resetAll() {
    _sessionSub?.cancel();
    _sessionSub = null;
    setState(() {
      _routePoints.clear();
      _childPosition = null;
      _code = null;
      _childJoined = false;
      _deviationAlertSent = false;
      _stage = _Stage.drawing;
      _status = 'Tap on map to draw the safe route';
    });
  }

  void _snack(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('👨‍👩‍👧 Parent — Draw & Monitor',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _stage == _Stage.monitoring
                ? const Color(0xFF00C851).withOpacity(0.15)
                : _status.contains('DEVIATION')
                    ? Colors.redAccent.withOpacity(0.15)
                    : Colors.white.withOpacity(0.05),
            child: Row(
              children: [
                Icon(
                  _stage == _Stage.monitoring
                      ? Icons.sensors_rounded
                      : Icons.info_outline_rounded,
                  color: _stage == _Stage.monitoring
                      ? const Color(0xFF00C851)
                      : Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_status,
                      style: TextStyle(
                          color: _stage == _Stage.monitoring
                              ? const Color(0xFF00C851)
                              : Colors.white70,
                          fontSize: 12)),
                ),
              ],
            ),
          ),

          if (_code != null && (_stage == _Stage.waitingChild || _stage == _Stage.monitoring))
            _buildCodeBanner(),

          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _parentPosition ?? const LatLng(17.3850, 78.4867),
                initialZoom: 15,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.crashaid.app',
                ),
                if (_routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 4,
                        color: const Color(0xFF3B6FFF).withOpacity(0.8),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    ..._routePoints.asMap().entries.map((e) {
                      final isLast = e.key == _routePoints.length - 1;
                      final isFirst = e.key == 0;
                      return Marker(
                        point: e.value,
                        width: 36,
                        height: 36,
                        child: Icon(
                          isLast
                              ? Icons.school_rounded
                              : isFirst
                                  ? Icons.home_rounded
                                  : Icons.circle,
                          color: isLast
                              ? const Color(0xFFFF8C3B)
                              : const Color(0xFF3B6FFF),
                          size: isLast || isFirst ? 28 : 12,
                        ),
                      );
                    }),
                    // Child's LIVE position — sourced from Firebase, not
                    // this device's own GPS.
                    if (_childPosition != null)
                      Marker(
                        point: _childPosition!,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00C851).withOpacity(0.3),
                            border: Border.all(
                                color: const Color(0xFF00C851), width: 2),
                          ),
                          child: const Icon(Icons.child_care_rounded,
                              color: Color(0xFF00C851), size: 20),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildCodeBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3B6FFF).withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B6FFF).withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.key_rounded, color: Color(0xFF3B6FFF), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_code!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4)),
                Text(
                  _childJoined
                      ? 'Child connected ✅'
                      : 'Waiting for child to enter this code…',
                  style: TextStyle(
                      color: _childJoined
                          ? const Color(0xFF00C851)
                          : Colors.white54,
                      fontSize: 11),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Clipboard.setData(ClipboardData(text: _code!)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, color: Colors.white70, size: 14),
                  SizedBox(width: 4),
                  Text('Copy', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF0A0A0F),
      child: Column(
        children: [
          if (_stage == _Stage.drawing && _isSettingRoute) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _routePoints.clear();
                      _isSettingRoute = false;
                      _status = 'Route cleared';
                    }),
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _finishRouteSetup,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Done'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B6FFF),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_stage == _Stage.drawing) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _startRouteSetup,
                icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                label: const Text('Draw Route'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF3B6FFF),
                  side: const BorderSide(color: Color(0xFF3B6FFF)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ] else if (_stage == _Stage.routeReady) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _startRouteSetup,
                    icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                    label: const Text('Redraw'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B6FFF),
                      side: const BorderSide(color: Color(0xFF3B6FFF)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _createSession,
                    icon: const Icon(Icons.qr_code_rounded, size: 18),
                    label: const Text('Get Code'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C851),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_stage == _Stage.creating) ...[
            const SizedBox(
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF00C851)),
                ),
              ),
            ),
          ] else if (_stage == _Stage.waitingChild || _stage == _Stage.monitoring) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _stopMonitoring,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('Stop Monitoring',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (widget.onSosTap != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onSosTap,
                  icon: const Icon(Icons.warning_rounded,
                      color: Color(0xFFFF3B3B)),
                  label: const Text('🚨 Send SOS Now',
                      style: TextStyle(
                          color: Color(0xFFFF3B3B), fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFF3B3B)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ] else if (_stage == _Stage.ended) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _resetAll,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Start New Session'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B6FFF),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

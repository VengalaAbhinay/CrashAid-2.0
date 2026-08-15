import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LiveTrackingMapScreen  (UI v2)
//
// Improvements over v1:
//  • User avatar with initials in bottom card
//  • Metric grid: Accuracy · Speed · Points used
//  • Elapsed-time + distance stats row below top bar
//  • Expiry shown as a green badge next to user name
//  • Coords row with monospaced font + inline Copy button
//  • Unified two-button action row (Maps / Share)
//  • Speed sourced from position.speed (wired via FirebaseDB field)
//  • Better colour semantics (green good accuracy, amber path cap warning)
//
// Dependencies (pubspec.yaml):
//   flutter_map: ^7.0.2
//   latlong2: ^0.9.1
//   firebase_database: ^11.1.4
//   url_launcher: ^6.3.2
// ─────────────────────────────────────────────────────────────────────────────

enum _SessionState { connecting, waitingGps, live, ended, notFound }

class LiveTrackingMapScreen extends StatefulWidget {
  final String sessionId;
  final String? shareUrl;

  const LiveTrackingMapScreen({
    super.key,
    required this.sessionId,
    this.shareUrl,
  });

  @override
  State<LiveTrackingMapScreen> createState() => _LiveTrackingMapScreenState();
}

class _LiveTrackingMapScreenState extends State<LiveTrackingMapScreen>
    with TickerProviderStateMixin {
  // ── Firebase ───────────────────────────────────────────────────────────────
  StreamSubscription<DatabaseEvent>? _dbSub;

  // ── Session state ──────────────────────────────────────────────────────────
  _SessionState _state = _SessionState.connecting;
  String _username = 'CrashAid';
  LatLng? _currentLatLng;
  double _accuracy = 0;
  double _speedKmh = 0;
  DateTime? _updatedAt;
  DateTime? _expiresAt;
  DateTime? _startedAt;
  bool _pathTruncated = false;
  final List<LatLng> _path = [];

  // ── Map ────────────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  bool _autoFollow = true;
  bool _mapReady = false;

  // ── Animation ──────────────────────────────────────────────────────────────
  late final AnimationController _pulseController;

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer? _clockTimer;
  String _lastUpdatedLabel = '–';

  // ── Computed ───────────────────────────────────────────────────────────────
  String get _shareUrl =>
      widget.shareUrl ??
      'https://crashaid-a1d3c.web.app/track?id=${widget.sessionId}';

  String get _avatarInitials {
    final parts = _username.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return _username.isNotEmpty ? _username[0].toUpperCase() : 'C';
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _clockTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {
          if (_updatedAt != null) _lastUpdatedLabel = _timeSince(_updatedAt!);
          // Check expiry even while stationary
          final isExpired =
              _expiresAt != null && _expiresAt!.isBefore(DateTime.now());
          if (isExpired && _state == _SessionState.live) {
            _state = _SessionState.ended;
          }
        });
      }
    });

    _listenToFirebase();
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    _clockTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Firebase ───────────────────────────────────────────────────────────────
  void _listenToFirebase() {
    final ref =
        FirebaseDatabase.instance.ref('live_tracking/${widget.sessionId}');

    _dbSub = ref.onValue.listen(
      (event) {
        final data = event.snapshot.value;
        if (!mounted) return;

        if (data == null) {
          setState(() => _state = _SessionState.notFound);
          return;
        }

        final map = Map<String, dynamic>.from(data as Map);

        if (map['username'] != null) _username = map['username'] as String;

        if (map['expires_at'] != null) {
          _expiresAt = DateTime.tryParse(map['expires_at'] as String);
        }
        if (map['started_at'] != null) {
          _startedAt = DateTime.tryParse(map['started_at'] as String);
        }

        _pathTruncated = map['path_truncated'] == true;

        // ── path ──────────────────────────────────────────────────────────
        final rawPath = map['path'];
        if (rawPath != null) {
          final entries = rawPath is List
              ? rawPath
              : (rawPath as Map).values.toList();
          final parsed = entries
              .whereType<Map>()
              .map((p) {
                final lat = (p['lat'] as num?)?.toDouble();
                final lng = (p['lng'] as num?)?.toDouble();
                if (lat == null || lng == null) return null;
                if (lat == 0 && lng == 0) return null;
                return LatLng(lat, lng);
              })
              .whereType<LatLng>()
              .toList();

          if (parsed.length != _path.length) {
            _path
              ..clear()
              ..addAll(parsed);
          }
        }

        // ── speed ─────────────────────────────────────────────────────────
        final speedMs = (map['speed'] as num?)?.toDouble() ?? 0;
        _speedKmh = speedMs >= 0 ? speedMs * 3.6 : 0;

        // ── ended / expired ───────────────────────────────────────────────
        final isExpired =
            _expiresAt != null && _expiresAt!.isBefore(DateTime.now());
        final isActive = map['active'] == true;

        if (!isActive || isExpired) {
          _accuracy = 0;
          _updatedAt = null;
          _lastUpdatedLabel = '–';
          if (_path.isNotEmpty) {
            _currentLatLng = _path.last;
          } else {
            final lat = (map['lat'] as num?)?.toDouble() ?? 0;
            final lng = (map['lng'] as num?)?.toDouble() ?? 0;
            if (lat != 0 && lng != 0) _currentLatLng = LatLng(lat, lng);
          }
          setState(() => _state = _SessionState.ended);
          return;
        }

        final lat = (map['lat'] as num?)?.toDouble() ?? 0;
        final lng = (map['lng'] as num?)?.toDouble() ?? 0;
        if (lat == 0 && lng == 0) {
          setState(() => _state = _SessionState.waitingGps);
          return;
        }

        final newLatLng = LatLng(lat, lng);
        _accuracy = (map['accuracy'] as num?)?.toDouble() ?? 0;
        if (map['updated_at'] != null) {
          _updatedAt = DateTime.tryParse(map['updated_at'] as String);
          _lastUpdatedLabel =
              _updatedAt != null ? _timeSince(_updatedAt!) : '–';
        }

        setState(() {
          _currentLatLng = newLatLng;
          _state = _SessionState.live;
        });

        if (_autoFollow) {
          _safeMoveMap(
            newLatLng,
            _mapController.camera.zoom < 15 ? 16 : _mapController.camera.zoom,
          );
        }
      },
      onError: (e) {
        if (mounted) setState(() => _state = _SessionState.notFound);
        debugPrint('🔴 LiveTrackingMap: Firebase error — $e');
      },
    );
  }

  // ── Map helpers ────────────────────────────────────────────────────────────
  void _safeMoveMap(LatLng point, double zoom) {
    if (_mapReady) {
      _mapController.move(point, zoom);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady) _mapController.move(point, zoom);
      });
    }
  }

  void _fitPath() {
    if (_path.isEmpty && _currentLatLng == null) return;
    final points = [..._path, if (_currentLatLng != null) _currentLatLng!];
    setState(() => _autoFollow = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      if (points.length == 1) {
        _mapController.move(points.first, 16);
        return;
      }
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
      );
    });
  }

  // ── String helpers ─────────────────────────────────────────────────────────
  String _timeSince(DateTime dt) {
    final diff = DateTime.now().difference(dt).inSeconds;
    if (diff < 5) return 'just now';
    if (diff < 60) return '${diff}s ago';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    return '${diff ~/ 3600}h ago';
  }

  String _expiryLabel() {
    if (_expiresAt == null) return '–';
    final mins = _expiresAt!.difference(DateTime.now()).inMinutes;
    if (mins <= 0) return 'Expiring…';
    if (mins >= 60) return '${mins ~/ 60}h ${mins % 60}m left';
    return '${mins}m left';
  }

  String _elapsedLabel() {
    if (_startedAt == null) return '–';
    final mins = DateTime.now().difference(_startedAt!).inMinutes;
    if (mins < 60) return '${mins}m';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  double _totalDistance() {
    if (_path.length < 2) return 0;
    const dist = Distance();
    double total = 0;
    for (int i = 1; i < _path.length; i++) {
      total += dist(_path[i - 1], _path[i]);
    }
    return total;
  }

  String _fmtDist(double m) {
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(2)} km';
  }

  // ── Share / copy ───────────────────────────────────────────────────────────
  void _shareLink() async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent('🚨 Track me live on CrashAid:\n$_shareUrl')}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _copyLink();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp not found — link copied!'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF00C851),
          ),
        );
      }
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _shareUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tracking link copied!'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF00C851),
      ),
    );
  }

  void _copyCoords() {
    if (_currentLatLng == null) return;
    final text =
        '${_currentLatLng!.latitude.toStringAsFixed(6)}, ${_currentLatLng!.longitude.toStringAsFixed(6)}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coordinates copied!'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF444466),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(),
          _buildStatsRow(),
          if (_pathTruncated) _buildTruncNotice(),
          _buildFabs(),
          _buildBottomCard(),
          if (_state == _SessionState.connecting) _buildConnectingOverlay(),
          if (_state == _SessionState.notFound) _buildNotFoundOverlay(),
          if (_state == _SessionState.waitingGps) _buildWaitingGpsOverlay(),
        ],
      ),
    );
  }

  // ── Map layer ──────────────────────────────────────────────────────────────
  Widget _buildMap() {
    final layers = <Widget>[
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.crashaid.app',
        maxNativeZoom: 19,
      ),
    ];

    if (_path.length >= 2) {
      layers.add(PolylineLayer(polylines: [
        Polyline(
          points: _path,
          color: const Color(0xCCFF3B3B),
          strokeWidth: 4,
        ),
      ]));
    }

    if (_currentLatLng != null && _accuracy > 0) {
      layers.add(CircleLayer(circles: [
        CircleMarker(
          point: _currentLatLng!,
          radius: _accuracy,
          useRadiusInMeter: true,
          color: const Color(0xFFFF3B3B).withValues(alpha: 0.08),
          borderColor: const Color(0xFFFF3B3B).withValues(alpha: 0.27),
          borderStrokeWidth: 1,
        ),
      ]));
    }

    if (_path.isNotEmpty) {
      layers.add(MarkerLayer(markers: [
        Marker(
          point: _path.first,
          width: 28,
          height: 28,
          child: _circleMarker('🟢', const Color(0xFF00C851)),
        ),
      ]));
    }

    if (_state == _SessionState.ended && _currentLatLng != null) {
      layers.add(MarkerLayer(markers: [
        Marker(
          point: _currentLatLng!,
          width: 28,
          height: 28,
          child: _circleMarker('🏁', const Color(0xFFFF8C3B)),
        ),
      ]));
    }

    if (_state == _SessionState.live && _currentLatLng != null) {
      layers.add(MarkerLayer(markers: [
        Marker(
          point: _currentLatLng!,
          width: 48,
          height: 48,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              final scale = 1.0 + _pulseController.value * 0.35;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                        border: Border.all(
                          color: const Color(0xFFFF3B3B).withValues(
                            alpha: 1 - _pulseController.value,
                          ),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  _circleMarker('🆘', const Color(0xFFFF3B3B), size: 36),
                ],
              );
            },
          ),
        ),
      ]));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLatLng ?? const LatLng(17.3850, 78.4867),
        initialZoom: 15,
        onMapReady: () {
          _mapReady = true;
          if (_autoFollow && _currentLatLng != null) {
            _mapController.move(_currentLatLng!, 16);
          }
        },
        onMapEvent: (event) {
          if (event is MapEventMoveStart &&
              event.source == MapEventSource.dragStart) {
            setState(() => _autoFollow = false);
          }
        },
      ),
      children: layers,
    );
  }

  Widget _circleMarker(String emoji, Color bg, {double size = 28}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.35),
            blurRadius: 6,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * 0.45)),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xE80A0A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () => Navigator.maybePop(context),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white70, size: 14),
              ),
            ),
            const SizedBox(width: 10),

            // LIVE badge
            _buildLiveBadge(),
            const SizedBox(width: 10),

            // Name + sub
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '🚨 $_username',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'CrashAid tracking',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11),
                  ),
                ],
              ),
            ),

            // Share icon
            GestureDetector(
              onTap: _shareLink,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.ios_share,
                    color: Colors.white70, size: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    Color badgeBg;
    Color badgeBorder;
    Color dotColor;
    String label;

    switch (_state) {
      case _SessionState.live:
        badgeBg = const Color(0xFF3B0000);
        badgeBorder = const Color(0x55FF3B3B);
        dotColor = const Color(0xFFFF3B3B);
        label = 'LIVE';
        break;
      case _SessionState.waitingGps:
        badgeBg = const Color(0xFF2A1F00);
        badgeBorder = const Color(0x55F0C040);
        dotColor = const Color(0xFFF0C040);
        label = 'GPS…';
        break;
      case _SessionState.ended:
        badgeBg = const Color(0xFF1A1A1A);
        badgeBorder = const Color(0x33888888);
        dotColor = const Color(0xFF888888);
        label = 'ENDED';
        break;
      default:
        badgeBg = const Color(0xFF1A1A1A);
        badgeBorder = const Color(0x33888888);
        dotColor = const Color(0xFF888888);
        label = '···';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              final isAnimated = _state == _SessionState.live ||
                  _state == _SessionState.waitingGps;
              return Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor.withValues(
                    alpha: isAnimated
                        ? 0.4 + 0.6 * (1 - _pulseController.value)
                        : 1.0,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                color: dotColor, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ── Stats row (distance + elapsed) ────────────────────────────────────────
  Widget _buildStatsRow() {
    final topOffset =
        MediaQuery.of(context).padding.top + 12 + 54 + 8; // below top bar

    return Positioned(
      top: topOffset,
      left: 16,
      child: Row(
        children: [
          _statPill(Icons.route_outlined, _fmtDist(_totalDistance())),
          const SizedBox(width: 6),
          _statPill(Icons.access_time, _elapsedLabel()),
        ],
      ),
    );
  }

  Widget _statPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xD20A0A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.45)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ── Truncation notice ──────────────────────────────────────────────────────
  Widget _buildTruncNotice() {
    return Positioned(
      bottom: 220,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF2A1A00),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x66FF8C3B)),
          ),
          child: const Text(
            '⚠️  Path truncated — only last 1000 points shown',
            style: TextStyle(color: Color(0xFFFF8C3B), fontSize: 11),
          ),
        ),
      ),
    );
  }

  // ── FABs ───────────────────────────────────────────────────────────────────
  Widget _buildFabs() {
    return Positioned(
      right: 12,
      bottom: 236,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _fab(
            icon: Icons.fit_screen,
            tooltip: 'Fit path',
            onTap: _fitPath,
          ),
          const SizedBox(height: 8),
          _fab(
            icon: _autoFollow ? Icons.my_location : Icons.location_searching,
            tooltip: _autoFollow ? 'Following' : 'Follow',
            active: _autoFollow,
            onTap: () {
              setState(() => _autoFollow = !_autoFollow);
              if (_autoFollow && _currentLatLng != null) {
                _safeMoveMap(_currentLatLng!, 16);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _fab({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFF3B3B) : const Color(0xD90A0A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }

  // ── Bottom card ────────────────────────────────────────────────────────────
  Widget _buildBottomCard() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: Color(0x1AFFFFFF)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // User row
            _buildUserRow(),
            const SizedBox(height: 12),

            // Metrics grid
            _buildMetricsGrid(),
            const SizedBox(height: 10),

            // Coordinates row
            _buildCoordsRow(),
            const SizedBox(height: 12),

            // Action buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildUserRow() {
    return Row(
      children: [
        // Avatar
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF3B0000),
            shape: BoxShape.circle,
            border: Border.all(
                color: const Color(0xFFFF3B3B).withValues(alpha: 0.4),
                width: 1.5),
          ),
          child: Center(
            child: Text(
              _avatarInitials,
              style: const TextStyle(
                  color: Color(0xFFFF3B3B),
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _username,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Updated $_lastUpdatedLabel',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Expiry badge
        if (_state != _SessionState.ended)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF002B14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF00C851).withValues(alpha: 0.3)),
            ),
            child: Text(
              _expiryLabel(),
              style: const TextStyle(
                  color: Color(0xFF00C851),
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1000),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFFFF8C3B).withValues(alpha: 0.3)),
            ),
            child: const Text(
              'Ended',
              style: TextStyle(
                  color: Color(0xFFFF8C3B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  Widget _buildMetricsGrid() {
    final accuracyLabel =
        _accuracy > 0 ? '±${_accuracy.round()} m' : '–';
    final accuracyColor = _accuracy > 0 && _accuracy <= 15
        ? const Color(0xFF00C851)
        : _accuracy > 30
            ? const Color(0xFFFF8C3B)
            : Colors.white;

    final speedLabel = _speedKmh > 3 ? '${_speedKmh.round()} km/h' : '0 km/h';

    final pathCount = _path.length;
    final pathLabel = '$pathCount/1000';
    final pathColor = pathCount >= 900
        ? const Color(0xFFFF3B3B)   // red:  ≥ 90 % full
        : pathCount >= 700
            ? const Color(0xFFFF8C3B) // amber: ≥ 70 % full
            : Colors.white;

    return Row(
      children: [
        _metricCell('Accuracy', accuracyLabel, valueColor: accuracyColor),
        const SizedBox(width: 6),
        _metricCell('Speed', speedLabel),
        const SizedBox(width: 6),
        _metricCell('Points', pathLabel, valueColor: pathColor),
      ],
    );
  }

  Widget _metricCell(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: 10,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                  color: valueColor ?? Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoordsRow() {
    final coords = _currentLatLng != null
        ? '${_currentLatLng!.latitude.toStringAsFixed(5)}, '
            '${_currentLatLng!.longitude.toStringAsFixed(5)}'
        : '–';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined,
              size: 14, color: Colors.white.withValues(alpha: 0.35)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              coords,
              style: const TextStyle(
                color: Color(0xFFAAAAAA),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _currentLatLng != null ? _copyCoords : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_outlined,
                      size: 12, color: Colors.white.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text(
                    'Copy',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () async {
              if (_currentLatLng == null) return;
              final uri = Uri.parse(
                'https://maps.google.com/?q='
                '${_currentLatLng!.latitude},'
                '${_currentLatLng!.longitude}',
              );
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B3B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_outlined, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Open in Maps',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _shareLink,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(Icons.link, color: Colors.white70, size: 18),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _shareLink,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(Icons.ios_share, color: Colors.white70, size: 17),
          ),
        ),
      ],
    );
  }

  // ── Overlays ───────────────────────────────────────────────────────────────
  Widget _buildConnectingOverlay() => _fullOverlay(
        emoji: '📡',
        title: 'Connecting…',
        subtitle: 'Loading tracking session',
        showSpinner: true,
      );

  Widget _buildNotFoundOverlay() => _fullOverlay(
        emoji: '🚨',
        title: 'Session not found',
        subtitle:
            'This tracking link is invalid or has expired.\nAsk for a new link.',
      );

  Widget _buildWaitingGpsOverlay() => _fullOverlay(
        emoji: '📍',
        title: 'Waiting for GPS…',
        subtitle: 'The device is acquiring a location fix.',
        showSpinner: true,
        transparent: true,
      );

  Widget _fullOverlay({
    required String emoji,
    required String title,
    required String subtitle,
    bool showSpinner = false,
    bool transparent = false,
  }) {
    return Positioned.fill(
      child: Container(
        color: transparent ? const Color(0xAA0D0D1A) : const Color(0xFF0D0D1A),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 14, height: 1.5),
              ),
            ),
            if (showSpinner) ...[
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFF3B3B),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
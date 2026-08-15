import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

class DirectionsMapScreen extends StatefulWidget {

  final String destinationName;
  final double destLat;
  final double destLon;
  final double userLat;
  final double userLon;

  const DirectionsMapScreen({
    super.key,
    required this.destinationName,
    required this.destLat,
    required this.destLon,
    required this.userLat,
    required this.userLon,
  });

  @override
  State<DirectionsMapScreen> createState() =>
      _DirectionsMapScreenState();
}

class _DirectionsMapScreenState
    extends State<DirectionsMapScreen> {

  late final MapController _mapController;
  bool _isOffline = false;
  bool _connectivityChecked = false;
  late LatLng _userLatLng;
  late LatLng _destLatLng;
  late double _distanceKm;

  @override
  void initState() {
    super.initState();

    _mapController = MapController();

    _userLatLng = LatLng(
      widget.userLat,
      widget.userLon,
    );

    _destLatLng = LatLng(
      widget.destLat,
      widget.destLon,
    );

    _distanceKm =
        Geolocator.distanceBetween(
          widget.userLat,
          widget.userLon,
          widget.destLat,
          widget.destLon,
        ) /
        1000;

    _checkConnectivity();
  }

  // ── CONNECTIVITY CHECK ────────────────────────────────────────────────────

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress
          .lookup('tile.openstreetmap.org')
          .timeout(const Duration(seconds: 4));
      if (result.isNotEmpty &&
          result[0].rawAddress.isNotEmpty) {
        setState(() {
          _isOffline = false;
          _connectivityChecked = true;
        });
        return;
      }
    } catch (_) {}
    setState(() {
      _isOffline = true;
      _connectivityChecked = true;
    });
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  LatLng get _center => LatLng(
        (widget.userLat + widget.destLat) / 2,
        (widget.userLon + widget.destLon) / 2,
      );

  double get _zoom {
    if (_distanceKm < 1) return 15;
    if (_distanceKm < 5) return 13;
    if (_distanceKm < 15) return 11;
    if (_distanceKm < 50) return 9;
    return 7;
  }

  String get _distanceText => _distanceKm < 1
      ? '${(_distanceKm * 1000).toStringAsFixed(0)} m'
      : '${_distanceKm.toStringAsFixed(1)} km';

  // ── NAVIGATION ────────────────────────────────────────────────────────────

  Future<void> _openGoogleMaps() async {

    final dest =
        '${widget.destLat},${widget.destLon}';
    final label =
        Uri.encodeComponent(widget.destinationName);

    // 1. geo: URI — any installed maps app
    final geoUri =
        Uri.parse('geo:$dest?q=$dest($label)');
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
      return;
    }

    // 2. Google Maps navigation intent
    final mapsIntent = Uri.parse(
      'google.navigation:q=${widget.destLat},'
      '${widget.destLon}&mode=d',
    );
    if (await canLaunchUrl(mapsIntent)) {
      await launchUrl(mapsIntent);
      return;
    }

    // 3. Browser fallback
    final webUri = Uri.parse(
      'https://maps.google.com/maps/dir/?api=1'
      '&origin=${widget.userLat},${widget.userLon}'
      '&destination=${widget.destLat},${widget.destLon}'
      '&travelmode=driving',
    );
    await launchUrl(
      webUri,
      mode: LaunchMode.externalApplication,
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF0A0A0F),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,

        iconTheme: const IconThemeData(
          color: Colors.white,
        ),

        title: Text(
          widget.destinationName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        actions: [
          if (_isOffline)
            Container(
              margin: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 8,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.5),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.wifi_off,
                    color: Colors.orange,
                    size: 13,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Offline',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),

      body: !_connectivityChecked

          // Show spinner while checking connectivity
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF3B3B),
              ),
            )

          : Column(
              children: [

                // ── INFO BAR ────────────────────────────
                _buildInfoBar(),

                // ── MAP AREA ────────────────────────────
                Expanded(
                  child: _isOffline
                      ? _buildOfflineMap()
                      : _buildOnlineMap(),
                ),

                // ── OFFLINE NOTICE ──────────────────────
                if (_isOffline)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    child: Builder(builder: (ctx) => Text(
                      AppLocalizations.of(ctx).offlineBanner,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    )),
                  ),
              ],
            ),
    );
  }

  // ── INFO BAR ──────────────────────────────────────────────────────────────

  Widget _buildInfoBar() {
    final loc = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF3B3B).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [

          const Icon(
            Icons.directions_car,
            color: Color(0xFFFF6B6B),
            size: 22,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  widget.destinationName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$_distanceText \${loc.away}',
                  style: const TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Navigate button — show always
          // (geo: URI works without internet)
          ElevatedButton.icon(
            onPressed: _openGoogleMaps,
            icon: const Icon(
              Icons.navigation,
              color: Colors.white,
              size: 15,
            ),
            label: Text(
              loc.navigate,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B3B),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ONLINE MAP (flutter_map + OSM tiles) ──────────────────────────────────

  Widget _buildOnlineMap() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(20),
      ),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: _zoom,
        ),
        children: [

          TileLayer(
            urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.crashaid',
            errorTileCallback: (tile, error, stackTrace) {},
            keepBuffer: 5,
          ),

          PolylineLayer(
            polylines: [
              Polyline(
                points: [_userLatLng, _destLatLng],
                strokeWidth: 4,
                color: const Color(0xFFFF3B3B),
                pattern: const StrokePattern.dotted(),
              ),
            ],
          ),

          MarkerLayer(
            markers: [
              _userMarker(),
              _destMarker(),
            ],
          ),
        ],
      ),
    );
  }

  // ── OFFLINE MAP (custom painted — no tiles needed) ────────────────────────

  Widget _buildOfflineMap() {
    // Uses _OfflineMapPainter — pure canvas drawing from coordinates only.
    // Zero network required: draws dark background, lat/lon grid, road hints,
    // dotted route line, distance badge, and user/destination markers entirely
    // from the two GPS points. Works 100% offline using places.db coordinates.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(20),
      ),
      child: Stack(
        children: [
          // Full-screen canvas map
          CustomPaint(
            painter: _OfflineMapPainter(
              userLat: widget.userLat,
              userLon: widget.userLon,
              destLat: widget.destLat,
              destLon: widget.destLon,
              distanceKm: _distanceKm,
            ),
            child: const SizedBox.expand(),
          ),

          // Coordinate labels at corners
          Positioned(
            top: 12,
            left: 12,
            child: _coordBadge(
              '📍 You',
              widget.userLat,
              widget.userLon,
              Colors.blue,
            ),
          ),

          Positioned(
            bottom: 12,
            right: 12,
            child: _coordBadge(
              '🏥 Dest',
              widget.destLat,
              widget.destLon,
              Colors.red,
            ),
          ),

          // Compass rose
          const Positioned(
            bottom: 12,
            left: 12,
            child: _CompassRose(),
          ),
        ],
      ),
    );
  }

  Widget _coordBadge(
    String label,
    double lat,
    double lon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '${lat.toStringAsFixed(4)}, '
            '${lon.toStringAsFixed(4)}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ── SHARED MARKERS ────────────────────────────────────────────────────────

  Marker _userMarker() => Marker(
        point: _userLatLng,
        width: 48,
        height: 48,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.blue,
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.my_location,
            color: Colors.blue,
            size: 24,
          ),
        ),
      );

  Marker _destMarker() => Marker(
        point: _destLatLng,
        width: 52,
        height: 52,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B3B),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3B3B)
                    .withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.local_hospital_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      );
}

// ── OFFLINE MAP PAINTER ───────────────────────────────────────────────────────
// Draws a proper styled map canvas using only the two GPS coordinates.
// No tiles required — works fully offline.

class _OfflineMapPainter extends CustomPainter {

  final double userLat;
  final double userLon;
  final double destLat;
  final double destLon;
  final double distanceKm;

  _OfflineMapPainter({
    required this.userLat,
    required this.userLon,
    required this.destLat,
    required this.destLon,
    required this.distanceKm,
  });

  // Convert lat/lon to canvas pixel with padding
  Offset _toPixel(
    double lat,
    double lon,
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
    Size size,
    double padding,
  ) {
    final usableW = size.width - padding * 2;
    final usableH = size.height - padding * 2;

    final x = padding +
        (lon - minLon) / (maxLon - minLon) * usableW;
    // Invert Y — latitude increases upward
    final y = padding +
        (1 - (lat - minLat) / (maxLat - minLat)) * usableH;

    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {

    const padding = 60.0;

    // ── BOUNDS (add margin around the two points) ──
    final latSpread = (destLat - userLat).abs();
    final lonSpread = (destLon - userLon).abs();
    final margin = math.max(latSpread, lonSpread) * 0.4 +
        0.01; // min margin 0.01 deg

    final minLat =
        math.min(userLat, destLat) - margin;
    final maxLat =
        math.max(userLat, destLat) + margin;
    final minLon =
        math.min(userLon, destLon) - margin;
    final maxLon =
        math.max(userLon, destLon) + margin;

    // ── BACKGROUND ────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF12172B),
    );

    // ── GRID LINES (lat/lon graticule) ─────────────
    _drawGrid(
      canvas, size,
      minLat, maxLat, minLon, maxLon, padding,
    );

    // ── SUBTLE ROAD-LIKE BACKGROUND LINES ─────────
    _drawRoadHints(
      canvas, size,
      minLat, maxLat, minLon, maxLon, padding,
    );

    // ── CONVERT POINTS ────────────────────────────
    final userPx = _toPixel(
      userLat, userLon,
      minLat, maxLat, minLon, maxLon,
      size, padding,
    );
    final destPx = _toPixel(
      destLat, destLon,
      minLat, maxLat, minLon, maxLon,
      size, padding,
    );

    // ── ROUTE GLOW ────────────────────────────────
    canvas.drawLine(
      userPx,
      destPx,
      Paint()
        ..color = const Color(0xFFFF3B3B).withValues(alpha: 0.2)
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round,
    );

    // ── ROUTE LINE (dashed) ───────────────────────
    _drawDashedLine(
      canvas,
      userPx,
      destPx,
      const Color(0xFFFF3B3B),
      4.0,
    );

    // ── MIDPOINT DISTANCE BADGE ───────────────────
    final mid = Offset(
      (userPx.dx + destPx.dx) / 2,
      (userPx.dy + destPx.dy) / 2,
    );
    _drawDistanceBadge(canvas, mid, distanceKm);

    // ── USER MARKER ───────────────────────────────
    _drawUserMarker(canvas, userPx);

    // ── DESTINATION MARKER ────────────────────────
    _drawDestMarker(canvas, destPx);
  }

  // ── GRID ──────────────────────────────────────────────────────────────────

  void _drawGrid(
    Canvas canvas,
    Size size,
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
    double padding,
  ) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1E2A45)
      ..strokeWidth = 1;

    const steps = 6;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;

      // Horizontal grid line (lat)
      final lat = minLat + t * (maxLat - minLat);
      final y = padding +
          (1 - t) * (size.height - padding * 2);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );

      // Lat label
      _drawLabel(
        canvas,
        lat.toStringAsFixed(3),
        Offset(4, y - 7),
        const Color(0xFF3A4A6A),
        9,
      );

      // Vertical grid line (lon)
      final lon = minLon + t * (maxLon - minLon);
      final x = padding +
          t * (size.width - padding * 2);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );

      // Lon label
      _drawLabel(
        canvas,
        lon.toStringAsFixed(3),
        Offset(x - 14, size.height - 14),
        const Color(0xFF3A4A6A),
        9,
      );
    }
  }

  // ── ROAD HINTS (faint diagonal lines suggesting streets) ─────────────────

  void _drawRoadHints(
    Canvas canvas,
    Size size,
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
    double padding,
  ) {
    final roadPaint = Paint()
      ..color = const Color(0xFF1A2540)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Draw a few representative "road" lines
    // based on the bounding box diagonal
    final w = size.width;
    final h = size.height;

    final roads = [
      [Offset(0, h * 0.3), Offset(w, h * 0.4)],
      [Offset(0, h * 0.6), Offset(w, h * 0.65)],
      [Offset(w * 0.3, 0), Offset(w * 0.4, h)],
      [Offset(w * 0.65, 0), Offset(w * 0.6, h)],
      [Offset(0, h * 0.15), Offset(w * 0.5, h * 0.55)],
      [Offset(w * 0.5, h * 0.45), Offset(w, h * 0.8)],
    ];

    for (final road in roads) {
      canvas.drawLine(road[0], road[1], roadPaint);
    }
  }

  // ── DASHED LINE ───────────────────────────────────────────────────────────

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double strokeWidth,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist =
        math.sqrt(dx * dx + dy * dy);
    const dashLen = 12.0;
    const gapLen = 8.0;
    final steps = dist / (dashLen + gapLen);

    for (int i = 0; i < steps; i++) {
      final t0 = i * (dashLen + gapLen) / dist;
      final t1 =
          (i * (dashLen + gapLen) + dashLen) / dist;
      if (t1 > 1) break;
      canvas.drawLine(
        Offset(
          start.dx + t0 * dx,
          start.dy + t0 * dy,
        ),
        Offset(
          start.dx + t1 * dx,
          start.dy + t1 * dy,
        ),
        paint,
      );
    }
  }

  // ── DISTANCE BADGE ────────────────────────────────────────────────────────

  void _drawDistanceBadge(
    Canvas canvas,
    Offset center,
    double distKm,
  ) {
    final text = distKm < 1
        ? '${(distKm * 1000).toStringAsFixed(0)} m'
        : '${distKm.toStringAsFixed(1)} km';

    final bgPaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFFFF3B3B).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: 72,
        height: 28,
      ),
      const Radius.circular(8),
    );

    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    _drawLabel(
      canvas,
      text,
      Offset(center.dx - 28, center.dy - 7),
      Colors.white,
      12,
    );
  }

  // ── USER MARKER ───────────────────────────────────────────────────────────

  void _drawUserMarker(Canvas canvas, Offset pos) {

    // Pulse ring
    canvas.drawCircle(
      pos,
      22,
      Paint()
        ..color = Colors.blue.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );

    // Outer ring
    canvas.drawCircle(
      pos,
      16,
      Paint()
        ..color = Colors.blue.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );

    // Inner fill
    canvas.drawCircle(
      pos,
      10,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.fill,
    );

    // White dot
    canvas.drawCircle(
      pos,
      4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Label
    _drawLabel(
      canvas,
      'You',
      Offset(pos.dx - 10, pos.dy - 30),
      Colors.blue,
      11,
    );
  }

  // ── DESTINATION MARKER ────────────────────────────────────────────────────

  void _drawDestMarker(Canvas canvas, Offset pos) {

    // Shadow glow
    canvas.drawCircle(
      pos,
      22,
      Paint()
        ..color = const Color(0xFFFF3B3B).withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );

    // Pin circle
    canvas.drawCircle(
      pos,
      14,
      Paint()
        ..color = const Color(0xFFFF3B3B)
        ..style = PaintingStyle.fill,
    );

    // White cross (hospital +)
    final crossPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(pos.dx, pos.dy - 7),
      Offset(pos.dx, pos.dy + 7),
      crossPaint,
    );
    canvas.drawLine(
      Offset(pos.dx - 7, pos.dy),
      Offset(pos.dx + 7, pos.dy),
      crossPaint,
    );

    // Label
    _drawLabel(
      canvas,
      'Destination',
      Offset(pos.dx - 30, pos.dy - 30),
      const Color(0xFFFF6B6B),
      11,
    );
  }

  // ── LABEL HELPER ──────────────────────────────────────────────────────────

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_OfflineMapPainter old) =>
      old.userLat != userLat ||
      old.userLon != userLon ||
      old.destLat != destLat ||
      old.destLon != destLon;
}

// ── COMPASS ROSE ─────────────────────────────────────────────────────────────

class _CompassRose extends StatelessWidget {

  const _CompassRose();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white24,
        ),
      ),
      child: const Center(
        child: Text(
          'N',
          style: TextStyle(
            color: Color(0xFFFF3B3B),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
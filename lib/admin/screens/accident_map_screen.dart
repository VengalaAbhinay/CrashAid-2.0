import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Full-screen map showing the accident location for a single SOS session.
/// Uses flutter_map + OpenStreetMap tiles (no API key required).
/// Also shows all active SOS locations if called from the dashboard map tab.
class AccidentMapScreen extends StatefulWidget {
  /// Single incident data — pass when viewing one incident.
  final Map<String, dynamic>? sessionData;

  /// Show ALL incidents — pass true when opening as the global map view.
  final bool showAll;

  const AccidentMapScreen({
    super.key,
    this.sessionData,
    this.showAll = false,
  });

  @override
  State<AccidentMapScreen> createState() => _AccidentMapScreenState();
}

class _AccidentMapScreenState extends State<AccidentMapScreen> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLng? get _singleLocation {
    if (widget.sessionData == null) return null;
    final d = widget.sessionData!;
    final lat = d['lat'] ?? d['latitude'];
    final lng = d['lng'] ?? d['longitude'];
    if (lat == null || lng == null) return null;
    return LatLng((lat as num).toDouble(), (lng as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.showAll ? 'All Accident Locations' : 'Accident Location',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_singleLocation != null)
            IconButton(
              icon: const Icon(Icons.open_in_new, color: Colors.blueAccent),
              tooltip: 'Open in Google Maps',
              onPressed: () {
                final loc = _singleLocation!;
                launchUrl(Uri.parse(
                  'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}',
                ));
              },
            ),
        ],
      ),
      body: widget.showAll ? _AllIncidentsMap() : _SingleIncidentMap(
        sessionData: widget.sessionData!,
        location: _singleLocation,
        mapController: _mapController,
      ),
    );
  }
}

// ─── Single Incident Map ───────────────────────────────────────────────────────

class _SingleIncidentMap extends StatelessWidget {
  final Map<String, dynamic> sessionData;
  final LatLng? location;
  final MapController mapController;

  const _SingleIncidentMap({
    required this.sessionData,
    required this.location,
    required this.mapController,
  });

  @override
  Widget build(BuildContext context) {
    if (location == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, color: Colors.white38, size: 48),
            SizedBox(height: 12),
            Text('Location data not available for this incident.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final userName = sessionData['userProfile']?['name']
        ?? sessionData['userName']
        ?? 'Unknown';
    final address = sessionData['address'] ?? sessionData['location'];

    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: location!,
            initialZoom: 15.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.crashaid.app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: location!,
                  width: 50, height: 60,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent, shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.warning_amber_rounded,
                            color: Colors.white, size: 22),
                      ),
                      CustomPaint(
                        painter: _TrianglePainter(Colors.redAccent),
                        size: const Size(12, 6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),

        // Info card overlay
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on,
                          color: Colors.redAccent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📍 Accident Location',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          Text(userName,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 20),
                _MapInfoRow(Icons.my_location, 'Coordinates',
                    '${location!.latitude.toStringAsFixed(5)}, ${location!.longitude.toStringAsFixed(5)}'),
                if (address != null && address.toString().isNotEmpty)
                  _MapInfoRow(Icons.place_outlined, 'Address', address.toString()),
              ],
            ),
          ),
        ),

        // Zoom controls
        Positioned(
          top: 16, right: 16,
          child: Column(
            children: [
              _MapBtn(icon: Icons.add, onTap: () {
                mapController.move(mapController.camera.center,
                    mapController.camera.zoom + 1);
              }),
              const SizedBox(height: 4),
              _MapBtn(icon: Icons.remove, onTap: () {
                mapController.move(mapController.camera.center,
                    mapController.camera.zoom - 1);
              }),
              const SizedBox(height: 4),
              _MapBtn(icon: Icons.center_focus_strong, onTap: () {
                mapController.move(location!, 15.0);
              }),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── All Incidents Map ─────────────────────────────────────────────────────────

class _AllIncidentsMap extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sos_sessions')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent));
        }

        final docs = snap.data!.docs;
        final markers = <Marker>[];
        final locations = <LatLng>[];

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final lat = data['lat'] ?? data['latitude'];
          final lng = data['lng'] ?? data['longitude'];
          if (lat == null || lng == null) continue;

          final pt = LatLng((lat as num).toDouble(), (lng as num).toDouble());
          locations.add(pt);

          // FIX: treat as active if endedAt is null AND status is not 'resolved'
          final statusRaw = data['status'] as String? ?? '';
          final isResolved = statusRaw.toLowerCase() == 'resolved'
              || data['endedAt'] != null;
          final isActive = !isResolved;

          final status = statusRaw.isNotEmpty
              ? statusRaw
              : (isActive ? 'Active' : 'Resolved');
          final color = _markerColor(isActive ? status : 'resolved');

          markers.add(Marker(
            point: pt,
            width: 36, height: 44,
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => IncidentPopup(doc: doc),
              )),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 16),
                  ),
                  CustomPaint(
                    painter: _TrianglePainter(color),
                    size: const Size(10, 5),
                  ),
                ],
              ),
            ),
          ));
        }

        final center = locations.isNotEmpty
            ? LatLng(
                locations.map((l) => l.latitude).reduce((a, b) => a + b) / locations.length,
                locations.map((l) => l.longitude).reduce((a, b) => a + b) / locations.length,
              )
            : const LatLng(17.3850, 78.4867); // Default: Hyderabad

        return FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 11.0),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.crashaid.app',
            ),
            MarkerLayer(markers: markers),
          ],
        );
      },
    );
  }

  Color _markerColor(String status) {
    return switch (status.toLowerCase()) {
      'active' || 'pending' => Colors.redAccent,
      'verified'            => Colors.blueAccent,
      'ambulance sent'      => Colors.purple,
      'police notified'     => Colors.cyan,
      'resolved'            => Colors.green,
      _                     => Colors.orangeAccent,
    };
  }
}

// ─── Small incident popup for "all map" marker taps ───────────────────────────

class IncidentPopup extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const IncidentPopup({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['userProfile']?['name'] ?? data['userName'] ?? 'Unknown';
    final ts = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : null;
    final status = data['status'] ?? (data['endedAt'] == null ? 'Active' : 'Resolved');

    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.25,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          children: [
            Text(name, style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(status, style: TextStyle(color: _statusColor(status))),
            if (ts != null) ...[
              const SizedBox(height: 4),
              Text('${ts.day}/${ts.month}/${ts.year}  ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String s) {
    return switch (s.toLowerCase()) {
      'active'   => Colors.redAccent,
      'resolved' => Colors.greenAccent,
      _          => Colors.orangeAccent,
    };
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

class _MapInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MapInfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, color: Colors.white38, size: 14),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ]),
      );
}

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      );
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
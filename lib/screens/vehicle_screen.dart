import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/osm_db.dart';
import '../l10n/app_localizations.dart';
import 'directions_map_screen.dart';

class VehicleScreen extends StatelessWidget {
  const VehicleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(loc.vehicleRescueTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            _topBanner(loc),
            _rescueCard(context, loc.towServices, loc.towServicesSub,
                Icons.local_shipping_rounded, const Color(0xFFFF8C3B), const Color(0xFF2D1A0A),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NearbyVehicleScreen(
                        label: loc.towServices, osmKey: "shop", osmValue: "car_repair")))),
            _rescueCard(context, loc.punctureShops, loc.punctureShopsSub,
                Icons.tire_repair, const Color(0xFFFF8C3B), const Color(0xFF2D1A0A),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NearbyVehicleScreen(
                        label: loc.punctureShops, osmKey: "shop", osmValue: "tyres")))),
            _rescueCard(context, loc.mechanics, loc.mechanicsSub,
                Icons.build_rounded, const Color(0xFFFFB347), const Color(0xFF2D1A0A),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NearbyVehicleScreen(
                        label: loc.mechanics, osmKey: "shop", osmValue: "car_repair")))),
            _rescueCard(context, loc.showrooms, loc.showroomsSub,
                Icons.car_rental, const Color(0xFFFF8C3B), const Color(0xFF2D1A0A),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NearbyVehicleScreen(
                        label: loc.showrooms, osmKey: "shop", osmValue: "car")))),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _topBanner(AppLocalizations loc) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D1A0A), Color(0xFF1A0F05)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFFF8C3B).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: const Color(0xFFFF8C3B).withValues(alpha: 0.15),
              blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8C3B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.car_repair_rounded, color: Color(0xFFFF8C3B), size: 40),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.vehicleBannerTitle,
                    style: const TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(loc.vehicleBannerSubtitle,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rescueCard(BuildContext context, String title, String subtitle,
      IconData icon, Color color, Color bg, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 10, spreadRadius: 1),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}

// ─── DATA MODEL ───
class NearbyPlace {
  final String name;
  final double lat;
  final double lon;
  final String? phone;
  final String? address;
  final double? distanceKm;

  const NearbyPlace({required this.name, required this.lat, required this.lon,
      this.phone, this.address, this.distanceKm});
}

// ─── NEARBY VEHICLE SCREEN ───
class NearbyVehicleScreen extends StatefulWidget {
  final String label;
  final String osmKey;
  final String osmValue;

  const NearbyVehicleScreen({super.key, required this.label,
      required this.osmKey, required this.osmValue});

  @override
  State<NearbyVehicleScreen> createState() => _NearbyVehicleScreenState();
}

class _NearbyVehicleScreenState extends State<NearbyVehicleScreen> {
  List<NearbyPlace> _places = [];
  bool _loading = true;
  String? _error;
  bool _noInternet = false;
  double? _userLat;
  double? _userLon;
  bool _offlineSource = false;

  static const Color _accent = Color(0xFFFF8C3B);

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<Position> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw Exception("Enable GPS");
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) throw Exception("Permission denied");
    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<List<NearbyPlace>> _queryWithFallback(double lat, double lon) async {
    // ── 1. Offline DB — exact category strings from places.db ──────────────
    try {
      final cats = OsmDb.dbCategories(widget.osmKey, widget.osmValue);
      final offlineResults = await OsmDb.queryNearby(
        userLat: lat,
        userLon: lon,
        categories: cats,
      );
      if (offlineResults.isNotEmpty) {
        _offlineSource = true;
        return offlineResults.map((p) => NearbyPlace(
          name: p.name, lat: p.lat, lon: p.lon,
          phone: p.phone, address: p.address, distanceKm: p.distanceKm,
        )).toList();
      }
    } catch (e) {
      debugPrint('Offline DB failed: $e');
    }

    // ── 2. Overpass mirrors in parallel ────────────────────────────────────
    _offlineSource = false;
    const int radius = 50000;
    final String query = '''
[out:json][timeout:25];
(
  node["${widget.osmKey}"="${widget.osmValue}"](around:$radius,$lat,$lon);
  way["${widget.osmKey}"="${widget.osmValue}"](around:$radius,$lat,$lon);
);
out center tags;
''';
    final mirrors = ['overpass-api.de', 'overpass.kumi.systems', 'lz4.overpass-api.de'];
    final futures = mirrors.map((mirror) async {
      final response = await http.post(
        Uri.parse("https://$mirror/api/interpreter"),
        headers: {"Content-Type": "application/x-www-form-urlencoded", "User-Agent": "CrashAid/1.0"},
        body: {"data": query},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final elements = (jsonDecode(response.body)["elements"] ?? []) as List;
        if (elements.isNotEmpty) return _parseElements(elements, lat, lon);
      }
      throw Exception("empty");
    }).toList();

    try {
      return await Future.any(futures.map((f) => f.then((r) {
        if (r.isEmpty) throw Exception("empty");
        return r;
      })));
    } catch (_) {
      debugPrint('All Overpass mirrors failed');
    }

    return [];
  }

  List<NearbyPlace> _parseElements(List<dynamic> elements, double userLat, double userLon) {
    final places = <NearbyPlace>[];
    for (final el in elements) {
      final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
      final String name = tags['name'] ?? "Unknown";
      final double? pLat = el['lat'] != null ? (el['lat'] as num).toDouble()
          : (el['center']?['lat'] as num?)?.toDouble();
      final double? pLon = el['lon'] != null ? (el['lon'] as num).toDouble()
          : (el['center']?['lon'] as num?)?.toDouble();
      if (pLat == null || pLon == null) continue;
      final dist = Geolocator.distanceBetween(userLat, userLon, pLat, pLon) / 1000;
      places.add(NearbyPlace(name: name, lat: pLat, lon: pLon,
          phone: tags['phone'] ?? tags['contact:phone'],
          address: tags['addr:street'], distanceKm: dist));
    }
    places.sort((a, b) => (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999));
    return places;
  }

  Future<void> _fetchAll() async {
    setState(() { _loading = true; _error = null; _noInternet = false; });
    try {
      final pos = await _getLocation();
      _userLat = pos.latitude;
      _userLon = pos.longitude;
      final places = await _queryWithFallback(pos.latitude, pos.longitude);
      if (!mounted) return;
      if (places.isEmpty && !_offlineSource) {
        setState(() { _places = []; _loading = false; _noInternet = true; });
      } else {
        setState(() { _places = places; _loading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _openDirections(NearbyPlace place) async {
    if (_userLat == null || _userLon == null) return;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DirectionsMapScreen(
          destinationName: place.name,
          destLat: place.lat,
          destLon: place.lon,
          userLat: _userLat!,
          userLon: _userLon!,
        ),
      ),
    );
  }

  Future<void> _callPlace(String phone) async {
    final Uri uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), ''));
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_offlineSource)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
              ),
              child: const Text("✅ Offline data",
                  style: TextStyle(color: Colors.green, fontSize: 11)),
            ),
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh, color: _accent),
              onPressed: _fetchAll,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _accent),
            SizedBox(height: 20),
            Text("Finding nearby services...",
                style: TextStyle(color: Color(0xFF888888), fontSize: 15)),
          ],
        ),
      );
    }

    if (_error != null) {
      final bool isGpsOff = _error!.contains('Enable GPS');
      final bool isPermDenied = _error!.contains('Permission denied');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, color: _accent, size: 60),
              const SizedBox(height: 20),
              Text(
                isGpsOff
                    ? 'Location is turned off.\nPlease enable GPS to find nearby services.'
                    : isPermDenied
                        ? 'Location permission denied.\nAllow location access for this app.'
                        : _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 20),
              if (isGpsOff)
                ElevatedButton.icon(
                  onPressed: () async {
                    await Geolocator.openLocationSettings();
                    await Future.delayed(const Duration(seconds: 1));
                    _fetchAll();
                  },
                  icon: const Icon(Icons.location_on, color: Colors.white, size: 18),
                  label: const Text('Enable Location', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: _accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                )
              else if (isPermDenied)
                ElevatedButton.icon(
                  onPressed: () async {
                    await Geolocator.openAppSettings();
                    await Future.delayed(const Duration(seconds: 1));
                    _fetchAll();
                  },
                  icon: const Icon(Icons.settings, color: Colors.white, size: 18),
                  label: const Text('Allow Permission', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: _accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                )
              else
                ElevatedButton.icon(
                  onPressed: _fetchAll,
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                  label: const Text('Retry', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: _accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
            ],
          ),
        ),
      );
    }

    if (_noInternet) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.wifi_off_rounded, color: Colors.orange, size: 48),
              ),
              const SizedBox(height: 20),
              const Text("No data available",
                  style: TextStyle(color: Colors.white, fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                "No offline data found for this category in your area,\n"
                "and online sources are unreachable.",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _fetchAll,
                icon: const Icon(Icons.refresh, color: _accent, size: 18),
                label: const Text("Try Again", style: TextStyle(color: _accent)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _accent.withValues(alpha: 0.6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_places.isEmpty) {
      return const Center(
          child: Text("No nearby services found.",
              style: TextStyle(color: Colors.white54)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: _places.length,
      itemBuilder: (context, i) {
        final place = _places[i];
        final distText = place.distanceKm! < 1
            ? '${(place.distanceKm! * 1000).toStringAsFixed(0)} m away'
            : '${place.distanceKm!.toStringAsFixed(1)} km away';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.car_repair_rounded, color: _accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(place.name, style: const TextStyle(color: Colors.white,
                            fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(distText, style: const TextStyle(
                            color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
                        if (place.address != null)
                          Text(place.address!, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openDirections(place),
                      icon: const Icon(Icons.directions, color: _accent, size: 16),
                      label: const Text("Directions",
                          style: TextStyle(color: _accent, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _accent.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (place.phone != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _callPlace(place.phone!),
                        icon: const Icon(Icons.phone, color: Colors.white, size: 16),
                        label: const Text("Call",
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
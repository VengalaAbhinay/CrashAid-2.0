import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/osm_db.dart';
import '../l10n/app_localizations.dart';
import 'directions_map_screen.dart';

class MedicalScreen extends StatelessWidget {
  const MedicalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(loc.medicalHelp,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            _topBanner(loc),
            _medicalCard(context, loc.callAmbulance, loc.callAmbulanceSub,
                Icons.emergency, const Color(0xFFFF3B3B), const Color(0xFF2D0F0F),
                onTap: () => _callNumber("108")),
            _medicalCard(context, loc.nearbyAmbulance, loc.nearbyAmbulanceSub,
                Icons.local_shipping, const Color(0xFFFF3B3B), const Color(0xFF2D0F0F),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NearbyPlacesScreen(
                        label: loc.nearbyAmbulance, osmKey: "emergency",
                        osmValue: "ambulance_station", accentColor: const Color(0xFFFF3B3B))))),
            _medicalCard(context, loc.hospitals, loc.hospitalsSub,
                Icons.local_hospital_rounded, const Color(0xFFFF6B6B), const Color(0xFF2D0F0F),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NearbyPlacesScreen(
                        label: loc.hospitals, osmKey: "amenity",
                        osmValue: "hospital", accentColor: const Color(0xFFFF3B3B))))),
            _medicalCard(context, loc.traumaCenters, loc.traumaCentersSub,
                Icons.medical_services, const Color(0xFFFF8C3B), const Color(0xFF2D1A0A),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NearbyPlacesScreen(
                        label: loc.traumaCenters, osmKey: "amenity",
                        osmValue: "hospital", extraFilter: "emergency",
                        accentColor: const Color(0xFFFF3B3B))))),
            _medicalCard(context, loc.bloodBanks, loc.bloodBanksSub,
                Icons.bloodtype, const Color(0xFFE53935), const Color(0xFF2D0F0F),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => NearbyPlacesScreen(
                        label: loc.bloodBanks, osmKey: "healthcare",
                        osmValue: "blood_bank", accentColor: const Color(0xFFFF3B3B))))),
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
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF2D0F0F), Color(0xFF1A0505)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFFF3B3B).withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: const Color(0xFFFF3B3B).withValues(alpha: 0.15),
            blurRadius: 20, spreadRadius: 2)],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFFFF3B3B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.emergency, color: Color(0xFFFF6B6B), size: 40),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.medicalBannerTitle,
                style: const TextStyle(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(loc.medicalBannerSubtitle,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12, height: 1.4)),
          ],
        )),
      ]),
    );
  }

  Widget _medicalCard(BuildContext context, String title, String subtitle,
      IconData icon, Color color, Color bg, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 10, spreadRadius: 1)],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
          ])),
          Icon(Icons.arrow_forward_ios, color: color, size: 16),
        ]),
      ),
    );
  }

  Future<void> _callNumber(String number) async {
    final Uri uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

// ─── DATA MODEL ──────────────────────────────────────────────────────────────
class NearbyPlace {
  final String name;
  final double lat, lon;
  final String? phone, address;
  final double? distanceKm;
  const NearbyPlace({required this.name, required this.lat, required this.lon,
      this.phone, this.address, this.distanceKm});
}

// ─── NEARBY PLACES SCREEN ────────────────────────────────────────────────────
class NearbyPlacesScreen extends StatefulWidget {
  final String label, osmKey, osmValue;
  final Color accentColor;
  final String? extraFilter;
  const NearbyPlacesScreen({super.key, required this.label,
      required this.osmKey, required this.osmValue,
      this.accentColor = const Color(0xFFFF3B3B), this.extraFilter});
  @override
  State<NearbyPlacesScreen> createState() => _NearbyPlacesScreenState();
}

class _NearbyPlacesScreenState extends State<NearbyPlacesScreen> {
  List<NearbyPlace> _places = [];
  bool _loading = true;
  String? _error;
  double? _userLat, _userLon;
  bool _offlineSource = false;
  bool _noInternet    = false;

  @override
  void initState() { super.initState(); _fetchAll(); }

  Future<Position> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw Exception("Enable GPS");
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) throw Exception("Permission denied");
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<List<NearbyPlace>> _queryWithFallback(double lat, double lon) async {
    try {
      final dbKey = widget.extraFilter == 'emergency' ? 'healthcare' : widget.osmKey;
      final dbVal = widget.extraFilter == 'emergency' ? 'emergency'  : widget.osmValue;
      final cats  = OsmDb.dbCategories(dbKey, dbVal);
      final offlineResults = await OsmDb.queryNearby(userLat: lat, userLon: lon, categories: cats);
      if (offlineResults.isNotEmpty) {
        _offlineSource = true;
        return offlineResults.map((p) => NearbyPlace(name: p.name, lat: p.lat, lon: p.lon,
            phone: p.phone, address: p.address, distanceKm: p.distanceKm)).toList();
      }
    } catch (e) { debugPrint('Offline DB: $e'); }

    _offlineSource = false;
    try {
      final nom = await _queryNominatim(lat, lon);
      if (nom.isNotEmpty) return nom;
    } catch (e) { debugPrint('Nominatim: $e'); }

    final mirrors = ['overpass-api.de','overpass.kumi.systems','lz4.overpass-api.de'];
    const int radius = 50000;
    final String query = widget.extraFilter == 'emergency'
        ? '[out:json][timeout:25];\n(\n  node["amenity"="hospital"](around:$radius,$lat,$lon);\n  way["amenity"="hospital"](around:$radius,$lat,$lon);\n  node["healthcare"="hospital"](around:$radius,$lat,$lon);\n  node["emergency"="yes"](around:$radius,$lat,$lon);\n);\nout center tags;\n'
        : '[out:json][timeout:25];\n(\n  node["${widget.osmKey}"="${widget.osmValue}"](around:$radius,$lat,$lon);\n  way["${widget.osmKey}"="${widget.osmValue}"](around:$radius,$lat,$lon);\n);\nout center tags;\n';

    final futures = mirrors.map((mirror) async {
      final res = await http.post(Uri.parse("https://$mirror/api/interpreter"),
          headers: {"Content-Type": "application/x-www-form-urlencoded", "User-Agent": "CrashAid/1.0"},
          body: {"data": query}).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final elements = (jsonDecode(res.body)["elements"] ?? []) as List;
        if (elements.isNotEmpty) return _parseElements(elements, lat, lon);
      }
      throw Exception("Empty from $mirror");
    }).toList();

    try {
      return await Future.any(futures.map((f) => f.then((r) {
        if (r.isEmpty) throw Exception("empty");
        return r;
      })));
    } catch (_) {}
    return [];
  }

  Future<List<NearbyPlace>> _queryNominatim(double lat, double lon) async {
    final String searchTerm = widget.extraFilter == 'emergency' ? 'hospital'
        : widget.osmValue == 'hospital' ? 'hospital'
        : widget.osmValue == 'blood_bank' ? 'blood bank'
        : widget.osmValue.replaceAll('_', ' ');
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(searchTerm)}'
      '&format=json&limit=30&addressdetails=1'
      '&viewbox=${lon-0.5},${lat+0.5},${lon+0.5},${lat-0.5}&bounded=1',
    );
    final res = await http.get(uri, headers: {
      'User-Agent': 'CrashAid/1.0 (emergency-app)', 'Accept-Language': 'en',
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final List data = jsonDecode(res.body) as List;
    if (data.isEmpty) return [];
    final places = data.map((item) {
      final pLat = double.parse(item['lat'] as String);
      final pLon = double.parse(item['lon'] as String);
      final dist = Geolocator.distanceBetween(lat, lon, pLat, pLon) / 1000;
      final address = item['address'] as Map<String, dynamic>?;
      return NearbyPlace(name: (item['display_name'] as String).split(',').first,
          lat: pLat, lon: pLon, address: address?['road'], distanceKm: dist);
    }).where((p) => p.distanceKm! <= 50).toList();
    places.sort((a, b) => (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999));
    return places;
  }

  List<NearbyPlace> _parseElements(List elements, double userLat, double userLon) {
    List<NearbyPlace> places = [];
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
      _userLat = pos.latitude; _userLon = pos.longitude;
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
    if (_userLat == null || _userLon == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DirectionsMapScreen(
        destinationName: place.name, destLat: place.lat, destLon: place.lon,
        userLat: _userLat!, userLon: _userLon!),
    ));
  }

  Future<void> _callPlace(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Widget _emergencyCallTile(String label, String number, Color color) =>
      SizedBox(width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _callPlace(number),
          icon: const Icon(Icons.call, color: Colors.white, size: 18),
          label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
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
                  border: Border.all(color: Colors.green.withValues(alpha: 0.5))),
              child: Text(loc.offlineData,
                  style: const TextStyle(color: Colors.green, fontSize: 11)),
            ),
          IconButton(onPressed: _fetchAll,
              icon: Icon(Icons.refresh, color: widget.accentColor)),
        ],
      ),
      body: _buildBody(loc),
    );
  }

  Widget _buildBody(AppLocalizations loc) {
    if (_loading) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: widget.accentColor),
        const SizedBox(height: 20),
        Text(loc.findingNearby,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 15)),
        const SizedBox(height: 8),
        Text(loc.checkingOffline,
            style: const TextStyle(color: Color(0xFF555555), fontSize: 12)),
      ]));
    }

    if (_error != null) {
      final isGpsOff   = _error!.contains('Enable GPS');
      final isPermDeny = _error!.contains('Permission denied');
      return Center(child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.location_off, color: widget.accentColor, size: 60),
          const SizedBox(height: 20),
          Text(isGpsOff ? loc.locationOff : isPermDeny ? loc.permissionDenied : _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 20),
          if (isGpsOff)
            ElevatedButton.icon(
              onPressed: () async {
                await Geolocator.openLocationSettings();
                await Future.delayed(const Duration(seconds: 1));
                _fetchAll();
              },
              icon: const Icon(Icons.location_on, color: Colors.white, size: 18),
              label: Text(loc.enableLocation,
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: widget.accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            )
          else if (isPermDeny)
            ElevatedButton.icon(
              onPressed: () async {
                await Geolocator.openAppSettings();
                await Future.delayed(const Duration(seconds: 1));
                _fetchAll();
              },
              icon: const Icon(Icons.settings, color: Colors.white, size: 18),
              label: Text(loc.allowPermission,
                  style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: widget.accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            )
          else
            ElevatedButton.icon(
              onPressed: _fetchAll,
              icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
              label: Text(loc.retry, style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: widget.accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
        ]),
      ));
    }

    if (_noInternet || (_places.isEmpty && !_offlineSource)) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle,
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
            child: const Icon(Icons.wifi_off_rounded, color: Colors.orange, size: 48),
          ),
          const SizedBox(height: 20),
          Text(loc.noInternet, style: const TextStyle(color: Colors.white,
              fontSize: 17, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(loc.noInternetMsg,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13, height: 1.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          _emergencyCallTile("🚑  Ambulance", "108", Colors.red),
          const SizedBox(height: 10),
          _emergencyCallTile("🆘  Emergency", "112", Colors.orange),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _fetchAll,
            icon: Icon(Icons.refresh, color: widget.accentColor, size: 18),
            label: Text(loc.tryAgain, style: TextStyle(color: widget.accentColor)),
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: widget.accentColor.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          ),
        ]),
      ));
    }

    if (_places.isEmpty) {
      return Center(child: Text(loc.noNearbyServices,
          style: const TextStyle(color: Colors.white54)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: _places.length,
      itemBuilder: (context, index) {
        final place = _places[index];
        final distText = place.distanceKm! < 1
            ? '${(place.distanceKm! * 1000).toStringAsFixed(0)} ${loc.mAway}'
            : '${place.distanceKm!.toStringAsFixed(1)} ${loc.kmAway}';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: widget.accentColor.withValues(alpha: 0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: widget.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.local_hospital_rounded,
                    color: widget.accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(place.name, style: const TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(distText, style: TextStyle(color: widget.accentColor,
                    fontSize: 12, fontWeight: FontWeight.w600)),
                if (place.address != null)
                  Text(place.address!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ])),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _openDirections(place),
                icon: Icon(Icons.directions, color: widget.accentColor, size: 16),
                label: Text(loc.directions,
                    style: TextStyle(color: widget.accentColor, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: widget.accentColor.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10)),
              )),
              if (place.phone != null) ...[
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  onPressed: () => _callPlace(place.phone!),
                  icon: const Icon(Icons.call, color: Colors.white, size: 16),
                  label: Text(loc.call,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                )),
              ],
            ]),
          ]),
        );
      },
    );
  }
}

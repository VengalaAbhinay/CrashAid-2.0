import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class HospitalMapScreen extends StatefulWidget {
  const HospitalMapScreen({super.key});

  @override
  State<HospitalMapScreen> createState() =>
      _HospitalMapScreenState();
}

class _HospitalMapScreenState
    extends State<HospitalMapScreen> {

  LatLng currentLocation =
      const LatLng(17.3850, 78.4867);

  bool isLoading = true;

  String errorMessage = "";

  /// True when the Overpass API could not be reached (no internet).
  /// The map still renders; only the hospital list is unavailable.
  bool isOffline = false;

  List<Map<String, dynamic>>
      hospitals = [];

  @override
  void initState() {
    super.initState();
    loadHospitals();
  }

  Future<void> loadHospitals() async {

    try {

      // LOCATION SERVICE
      bool serviceEnabled =
          await Geolocator
              .isLocationServiceEnabled();

      if (!serviceEnabled) {

        setState(() {
          errorMessage =
              "Location services disabled";
          isLoading = false;
        });

        return;
      }

      // LOCATION PERMISSION
      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission ==
          LocationPermission.denied) {

        permission =
            await Geolocator
                .requestPermission();

        if (permission ==
            LocationPermission.denied) {

          setState(() {
            errorMessage =
                "Location permission denied";
            isLoading = false;
          });

          return;
        }
      }

      // CURRENT LOCATION
      Position position =
          await Geolocator
              .getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.high,
      );

      currentLocation = LatLng(
        position.latitude,
        position.longitude,
      );

      // OVERPASS QUERY
      String query = """
[out:json];
(
  node["amenity"="hospital"](around:15000,
  ${position.latitude},
  ${position.longitude});

  way["amenity"="hospital"](around:15000,
  ${position.latitude},
  ${position.longitude});

  relation["amenity"="hospital"](around:15000,
  ${position.latitude},
  ${position.longitude});
);
out center;
""";

     final url = Uri.parse(
  "https://overpass.kumi.systems/api/interpreter",
);
      

      final response = await http.post(

        url,

        headers: {
          "Content-Type":
              "application/x-www-form-urlencoded",
        },

        body: {
          "data": query,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {

        // Network reachable but bad response — show map without hospital list
        setState(() {
          isOffline = true;
          isLoading = false;
        });

        return;
      }

      final data =
          json.decode(response.body);

      List elements =
          data['elements'] ?? [];

      hospitals = [];

      for (var e in elements) {

        String name =
            e['tags']?['name'] ??
                "Unnamed Hospital";

        double? lat;
        double? lon;

        // NODE
        if (e['lat'] != null &&
            e['lon'] != null) {

          lat = e['lat'];
          lon = e['lon'];
        }

        // WAY / RELATION
        else if (e['center'] != null) {

          lat = e['center']['lat'];
          lon = e['center']['lon'];
        }

        if (lat != null &&
            lon != null) {

          hospitals.add({

            "name": name,

            "location":
                LatLng(lat, lon),
          });
        }
      }

      setState(() {
        isLoading = false;
      });

    } catch (e) {

      // Any exception (SocketException, TimeoutException, etc.) means we're
      // offline or the server is unreachable.  Show the map at the last known
      // GPS position with an offline notice instead of a blank error screen.
      setState(() {
        isOffline = true;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          "Nearby Hospitals",
        ),
      ),

      body: isLoading

          ? const Center(
              child:
                  CircularProgressIndicator(),
            )

          : errorMessage.isNotEmpty

              ? Center(
                  child: Text(
                    errorMessage,
                    style:
                        const TextStyle(
                      fontSize: 18,
                    ),
                  ),
                )

              : Column(
                  children: [

                    // ── OFFLINE BANNER ──────────────────────────────
                    if (isOffline)
                      Container(
                        width: double.infinity,
                        color: Colors.orange.shade800,
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 12,
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.wifi_off,
                                color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "You're offline — map tiles may not load. "
                                "Hospital list unavailable.",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // MAP
                    SizedBox(
                      height: isOffline ? 320 : 350,

                      child: FlutterMap(

                        options:
                            MapOptions(
                          initialCenter:
                              currentLocation,

                          initialZoom: 11,
                        ),

                        children: [

                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',

                            userAgentPackageName:
                                'com.example.crashaid',

                            // Show a light-grey placeholder when a tile
                            // fails to load (e.g. offline).
                            errorTileCallback: (tile, error, stackTrace) {
                              // Silently swallow tile errors so the map
                              // widget itself doesn't crash offline.
                            },

                            // Reuse any already-cached tiles
                            keepBuffer: 5,
                          ),

                          MarkerLayer(
                            markers: [

                              // USER LOCATION
                              Marker(
                                point:
                                    currentLocation,

                                width: 80,
                                height: 80,

                                child:
                                    const Icon(
                                  Icons
                                      .location_on,

                                  color:
                                      Colors.blue,

                                  size: 45,
                                ),
                              ),

                              // HOSPITALS (empty when offline)
                              ...hospitals.map(

                                (hospital) {

                                  return Marker(
                                    point:
                                        hospital[
                                            'location'],

                                    width: 80,
                                    height: 80,

                                    child:
                                        const Icon(
                                      Icons
                                          .local_hospital,

                                      color:
                                          Colors.red,

                                      size: 40,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // LIST
                    Expanded(
                      child: isOffline

                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.wifi_off,
                                      size: 40, color: Colors.grey),
                                  SizedBox(height: 10),
                                  Text(
                                    "No internet connection.\nConnect to load nearby hospitals.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 14),
                                  ),
                                ],
                              ),
                            )

                          : hospitals.isEmpty

                              ? const Center(
                                  child: Text(
                                    "No hospitals found nearby",
                                  ),
                                )

                              : ListView.builder(

                                  itemCount:
                                      hospitals
                                          .length,

                                  itemBuilder:
                                      (
                                        context,
                                        index,
                                      ) {

                                    final hospital =
                                        hospitals[
                                            index];

                                    return Card(

                                      margin:
                                          const EdgeInsets
                                              .all(
                                                  10),

                                      child:
                                          ListTile(

                                        leading:
                                            const Icon(
                                          Icons
                                              .local_hospital,

                                          color:
                                              Colors.red,
                                        ),

                                        title:
                                            Text(
                                          hospital[
                                              'name'],
                                        ),

                                        subtitle:
                                            const Text(
                                          "Nearby Hospital",
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
    );
  }
}

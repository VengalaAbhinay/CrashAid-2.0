import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/pothole_service.dart';

class PotholeMapScreen extends StatefulWidget {
  const PotholeMapScreen({super.key});

  @override
  State<PotholeMapScreen> createState() => _PotholeMapScreenState();
}

class _PotholeMapScreenState extends State<PotholeMapScreen> {
  LatLng currentLocation = const LatLng(17.3850, 78.4867);

  bool isLoading = true;
  String errorMessage = "";

  List<PotholeReport> potholes = [];

  @override
  void initState() {
    super.initState();
    _loadLocationAndPotholes();

    // Keep the map live as other users submit reports.
    PotholeService.watchAll().listen((reports) {
      if (mounted) {
        setState(() => potholes = reports);
      }
    });
  }

  Future<void> _loadLocationAndPotholes() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          errorMessage = "Location services disabled";
          isLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            errorMessage = "Location permission denied";
            isLoading = false;
          });
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      currentLocation = LatLng(position.latitude, position.longitude);

      final reports = await PotholeService.fetchAll();

      setState(() {
        potholes = reports;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = "Could not load map: $e";
        isLoading = false;
      });
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'High':
        return Colors.red;
      case 'Low':
        return Colors.amber;
      default:
        return Colors.orange;
    }
  }

  Future<void> _showReportDialog() async {
    String selectedSeverity = 'Medium';
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text('Report Pothole', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reports at your current location.',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 16),
                  const Text('Severity', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Low', 'Medium', 'High'].map((s) {
                      final isSelected = selectedSeverity == s;
                      return ChoiceChip(
                        label: Text(s),
                        selected: isSelected,
                        selectedColor: _severityColor(s).withValues(alpha: 0.3),
                        labelStyle: TextStyle(
                          color: isSelected ? _severityColor(s) : Colors.white70,
                        ),
                        onSelected: (_) => setDialogState(() => selectedSeverity = s),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Optional note (e.g. "large, near junction")',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final id = await PotholeService.reportPothole(
        lat: currentLocation.latitude,
        lng: currentLocation.longitude,
        severity: selectedSeverity,
        note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(id != null
                ? 'Pothole reported — thanks!'
                : 'Could not submit report. Try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text('Pothole Map'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showReportDialog,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Report Pothole'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                )
              : FlutterMap(
                  options: MapOptions(
                    initialCenter: currentLocation,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.crashaid_hackathon_2026',
                      errorTileCallback: (tile, error, stackTrace) {
                        // Silently swallow tile errors so the map doesn't crash offline.
                      },
                      keepBuffer: 5,
                    ),
                    MarkerLayer(
                      markers: [
                        // USER LOCATION
                        Marker(
                          point: currentLocation,
                          width: 80,
                          height: 80,
                          child: const Icon(Icons.location_on, color: Colors.blue, size: 45),
                        ),

                        // POTHOLE REPORTS
                        ...potholes.map((p) {
                          return Marker(
                            point: LatLng(p.lat, p.lng),
                            width: 70,
                            height: 70,
                            child: GestureDetector(
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${p.severity} severity'
                                      '${p.note != null ? " — ${p.note}" : ""}',
                                    ),
                                  ),
                                );
                              },
                              child: Icon(Icons.warning_rounded,
                                  color: _severityColor(p.severity), size: 34),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
    );
  }
}

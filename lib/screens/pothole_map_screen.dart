import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../services/pothole_service.dart';

/// PotholeMapScreen — "Features to Add" implementation:
///
/// 1. Automatic Location   — PotholeService captures a fresh GPS fix at
///                            submit time; the new marker appears exactly
///                            there via the live watchAll() stream.
/// 2. Photo Evidence       — camera/gallery picker, uploaded to Firebase
///                            Storage and attached to the report.
/// 3. Pothole Severity     — Small / Medium / Large-Critical selector.
/// 4. Simple Report        — hazard type: Pothole / Road damage /
///                            Dangerous road / Other hazard.
/// 5. Pothole Map          — severity-coloured markers + legend
///                            (green = Small, orange = Medium, red = Severe).
/// 6. Crowd Confirmation   — "I found this pothole too" with a live count.
class PotholeMapScreen extends StatefulWidget {
  const PotholeMapScreen({super.key});

  @override
  State<PotholeMapScreen> createState() => _PotholeMapScreenState();
}

class _PotholeMapScreenState extends State<PotholeMapScreen> {
  static const _severityGreen = Color(0xFF00C851); // Small
  static const _severityOrange = Color(0xFFFF8800); // Medium
  static const _severityRed = Color(0xFFFF3B3B); // Severe / Large-Critical

  static const _severityOptions = [
    {'value': 'Low', 'label': 'Small'},
    {'value': 'Medium', 'label': 'Medium'},
    {'value': 'High', 'label': 'Large/Critical'},
  ];

  static const _typeOptions = [
    {'value': 'Pothole', 'icon': Icons.circle_rounded},
    {'value': 'Road damage', 'icon': Icons.warning_rounded},
    {'value': 'Dangerous road', 'icon': Icons.report_problem_rounded},
    {'value': 'Other hazard', 'icon': Icons.error_outline_rounded},
  ];

  final MapController _mapController = MapController();
  LatLng currentLocation = const LatLng(17.3850, 78.4867);

  bool isLoading = true;
  String errorMessage = '';

  List<PotholeReport> potholes = [];

  @override
  void initState() {
    super.initState();
    _loadLocationAndPotholes();

    // Keep the map live as other users submit reports or confirm existing
    // ones (Crowd Confirmation).
    PotholeService.watchAll().listen(
      (reports) {
        if (mounted) setState(() => potholes = reports);
      },
      onError: (e) {
        debugPrint('🔴 PotholeMapScreen: watchAll stream error — $e');
      },
    );
  }

  Future<void> _loadLocationAndPotholes() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          errorMessage = 'Location services disabled';
          isLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            errorMessage = 'Location permission denied';
            isLoading = false;
          });
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
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
        errorMessage = 'Could not load map: $e';
        isLoading = false;
      });
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'High':
        return _severityRed;
      case 'Low':
        return _severityGreen;
      default:
        return _severityOrange;
    }
  }

  String _severityDisplayLabel(String severity) {
    switch (severity) {
      case 'High':
        return 'Large/Critical';
      case 'Low':
        return 'Small';
      default:
        return 'Medium';
    }
  }

  IconData _typeIcon(String type) {
    for (final t in _typeOptions) {
      if (t['value'] == type) return t['icon'] as IconData;
    }
    return Icons.warning_rounded;
  }

  // ── REPORT DIALOG (Photo Evidence + Severity + Simple Report type) ────
  Future<void> _showReportDialog() async {
    String selectedSeverity = 'Medium';
    String selectedType = 'Pothole';
    final noteController = TextEditingController();
    XFile? photo;
    bool submitting = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickPhoto(ImageSource source) async {
              final picker = ImagePicker();
              final file = await picker.pickImage(
                source: source,
                maxWidth: 1000,
                imageQuality: 75,
              );
              if (file != null) setDialogState(() => photo = file);
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text('Report Hazard', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Automatic Location
                    Row(
                      children: [
                        const Icon(Icons.my_location_rounded, color: Colors.white54, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Your exact GPS location is captured automatically when you submit.',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Simple Report — hazard type
                    const Text('What are you reporting?',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _typeOptions.map((t) {
                        final value = t['value'] as String;
                        final isSelected = selectedType == value;
                        return ChoiceChip(
                          avatar: Icon(t['icon'] as IconData,
                              size: 16, color: isSelected ? Colors.white : Colors.white54),
                          label: Text(value),
                          selected: isSelected,
                          selectedColor: const Color(0xFF3B6FFF),
                          backgroundColor: const Color(0xFF262630),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 12,
                          ),
                          onSelected: (_) => setDialogState(() => selectedType = value),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Pothole Severity
                    const Text('Severity',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _severityOptions.map((s) {
                        final value = s['value']!;
                        final label = s['label']!;
                        final isSelected = selectedSeverity == value;
                        final color = _severityColor(value);
                        return ChoiceChip(
                          label: Text(label),
                          selected: isSelected,
                          selectedColor: color.withValues(alpha: 0.3),
                          backgroundColor: const Color(0xFF262630),
                          labelStyle: TextStyle(
                            color: isSelected ? color : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(color: isSelected ? color : Colors.transparent),
                          onSelected: (_) => setDialogState(() => selectedSeverity = value),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Photo Evidence
                    const Text('Photo (optional)',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (photo != null)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(photo!.path),
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => setDialogState(() => photo = null),
                              child: const CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors.black87,
                                child: Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickPhoto(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white70),
                              label: const Text('Take photo', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickPhoto(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_rounded, size: 16, color: Colors.white70),
                              label: const Text('Upload', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Optional note (e.g. "large, near junction")',
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() => submitting = true);
                          final id = await PotholeService.reportPothole(
                            severity: selectedSeverity,
                            type: selectedType,
                            note: noteController.text.trim().isEmpty
                                ? null
                                : noteController.text.trim(),
                            photo: photo != null ? File(photo!.path) : null,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, id != null);
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (confirmed == true) {
      // The report used a freshly-captured GPS fix which may differ from
      // wherever the map is currently centered — recenter so the new
      // marker is guaranteed to be visible instead of possibly off-screen.
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 8));
        final newLoc = LatLng(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() => currentLocation = newLoc);
          _mapController.move(newLoc, 16);
        }
      } catch (_) {
        // Non-critical — the live watchAll() stream will still update the
        // marker list even if recentring fails.
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(confirmed == true
            ? 'Hazard reported — thanks for helping other drivers!'
            : confirmed == false
                ? 'Report cancelled'
                : 'Could not submit report. Try again.'),
      ),
    );
  }

  // ── MARKER TAP: DETAILS + CROWD CONFIRMATION ───────────────────────────
  Future<void> _showReportDetails(PotholeReport p) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    bool alreadyConfirmed = p.confirmedByUser(uid);
    bool confirming = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF15151F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_typeIcon(p.type), color: _severityColor(p.severity), size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(p.type,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _severityColor(p.severity).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _severityColor(p.severity).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            _severityDisplayLabel(p.severity),
                            style: TextStyle(
                                color: _severityColor(p.severity),
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (p.note != null && p.note!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(p.note!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                    if (p.photoUrl != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          p.photoUrl!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const SizedBox(
                              height: 180,
                              child: Center(
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          },
                          errorBuilder: (_, __, ___) => const SizedBox(
                            height: 60,
                            child: Center(
                                child: Text('Photo unavailable',
                                    style: TextStyle(color: Colors.white38, fontSize: 12))),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.groups_rounded, color: Colors.white54, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          p.confirmCount == 0
                              ? 'No confirmations yet'
                              : 'Confirmed by ${p.confirmCount} ${p.confirmCount == 1 ? 'person' : 'people'}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: alreadyConfirmed || confirming
                            ? null
                            : () async {
                                setSheetState(() => confirming = true);
                                final ok = await PotholeService.confirmPothole(p.id);
                                setSheetState(() {
                                  confirming = false;
                                  if (ok) alreadyConfirmed = true;
                                });
                              },
                        icon: Icon(
                          alreadyConfirmed ? Icons.check_circle_rounded : Icons.thumb_up_rounded,
                          size: 18,
                        ),
                        label: Text(alreadyConfirmed
                            ? 'You confirmed this'
                            : confirming
                                ? 'Confirming…'
                                : 'I found this pothole too'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              alreadyConfirmed ? Colors.white12 : const Color(0xFF3B6FFF),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── LEGEND ──────────────────────────────────────────────────────────
  Widget _legend() {
    Widget dot(Color c) => Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );

    Widget row(Color c, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            dot(c),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        );

    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(_severityGreen, 'Small'),
            row(_severityOrange, 'Medium'),
            row(_severityRed, 'Severe'),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
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
        label: const Text('Report Hazard'),
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
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
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

                            // HAZARD REPORTS — size grows slightly with
                            // confirmation count to visually surface
                            // higher-confidence reports.
                            ...potholes.map((p) {
                              final size = 30.0 + (p.confirmCount.clamp(0, 6) * 2);
                              return Marker(
                                point: LatLng(p.lat, p.lng),
                                width: size + 20,
                                height: size + 20,
                                child: GestureDetector(
                                  onTap: () => _showReportDetails(p),
                                  child: Icon(
                                    _typeIcon(p.type),
                                    color: _severityColor(p.severity),
                                    size: size,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                    _legend(),
                  ],
                ),
    );
  }
}
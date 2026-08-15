import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'accident_map_screen.dart';

/// Full incident details — opened when admin taps an alert card.
/// Shows: status pipeline, user profile, medical data, emergency contacts,
/// vehicle info, location, and live tracking link.
class IncidentDetailsScreen extends StatefulWidget {
  final QueryDocumentSnapshot sessionDoc;
  final bool canModify;

  const IncidentDetailsScreen(
      {super.key, required this.sessionDoc, this.canModify = true});

  @override
  State<IncidentDetailsScreen> createState() => _IncidentDetailsScreenState();
}

class _IncidentDetailsScreenState extends State<IncidentDetailsScreen> {
  bool _updatingStatus = false;

  // We stream the session so status changes update live on this screen too.
  Stream<DocumentSnapshot> get _sessionStream => FirebaseFirestore.instance
      .collection('sos_sessions')
      .doc(widget.sessionDoc.id)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _sessionStream,
      builder: (context, snap) {
        final data = snap.data?.exists == true
            ? snap.data!.data() as Map<String, dynamic>
            : widget.sessionDoc.data() as Map<String, dynamic>;

        final userId = data['userId'] as String? ?? '';
        final status = data['status'] as String? ??
            (data['endedAt'] == null ? 'Active' : 'Resolved');

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1A1A1A),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Incident Details',
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text('ID: ${widget.sessionDoc.id.substring(0, 12)}…',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
            actions: [
              // Open map button
              IconButton(
                icon: const Icon(Icons.map_outlined, color: Colors.blueAccent),
                tooltip: 'View on Map',
                onPressed: () => _openMap(context, data),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Status Pipeline ────────────────────────────────────────
                _StatusPipeline(
                  currentStatus: status,
                  docId: widget.sessionDoc.id,
                  onUpdating: (v) => setState(() => _updatingStatus = v),
                  isUpdating: _updatingStatus,
                  canModify: widget.canModify,
                ),
                const SizedBox(height: 20),

                // ── User Profile (fetched from users collection) ───────────
                if (userId.isNotEmpty)
                  _UserProfileSection(
                    userId: userId,
                    sessionData: data,
                  )
                else
                  _SessionDataSection(data: data),

                const SizedBox(height: 20),

                // ── Location Section ───────────────────────────────────────
                _LocationSection(data: data),

                const SizedBox(height: 20),

                // ── Live Tracking Section ──────────────────────────────────
                _LiveTrackingSection(userId: userId, sessionData: data),

                const SizedBox(height: 20),

                // ── Incident Metadata ──────────────────────────────────────
                _MetaSection(data: data),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openMap(BuildContext context, Map<String, dynamic> data) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AccidentMapScreen(sessionData: data),
    ));
  }
}

// ─── Status Pipeline ──────────────────────────────────────────────────────────

class _StatusPipeline extends StatelessWidget {
  final String currentStatus;
  final String docId;
  final ValueChanged<bool> onUpdating;
  final bool isUpdating;
  final bool canModify;

  const _StatusPipeline({
    required this.currentStatus,
    required this.docId,
    required this.onUpdating,
    required this.isUpdating,
    this.canModify = true,
  });

  static const _steps = [
    ('Pending', Icons.hourglass_empty),
    ('Verified', Icons.verified_outlined),
    ('Ambulance Sent', Icons.local_hospital_outlined),
    ('Police Notified', Icons.local_police_outlined),
    ('Resolved', Icons.check_circle_outline),
  ];

  int get _currentIndex {
    final s = currentStatus.toLowerCase();
    if (s == 'active') return 0;
    for (var i = 0; i < _steps.length; i++) {
      if (_steps[i].$1.toLowerCase() == s) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Status Management',
      icon: Icons.track_changes,
      iconColor: Colors.orangeAccent,
      child: Column(
        children: [
          // Pipeline indicators
          SizedBox(
            height: 80,
            child: Row(
              children: List.generate(_steps.length * 2 - 1, (i) {
                if (i.isOdd) {
                  // connector line
                  final stepBefore = (i - 1) ~/ 2;
                  final passed = stepBefore < _currentIndex;
                  return Expanded(
                    child: Container(
                      height: 2,
                      color: passed
                          ? Colors.redAccent.withValues(alpha: 0.7)
                          : Colors.white12,
                    ),
                  );
                }
                final stepIdx = i ~/ 2;
                final isDone = stepIdx < _currentIndex;
                final isCurrent = stepIdx == _currentIndex;
                final step = _steps[stepIdx];
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone
                            ? Colors.redAccent
                            : isCurrent
                                ? Colors.redAccent.withValues(alpha: 0.25)
                                : Colors.white10,
                        border: Border.all(
                          color: isDone || isCurrent
                              ? Colors.redAccent
                              : Colors.white24,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(step.$2,
                          color: isDone
                              ? Colors.white
                              : isCurrent
                                  ? Colors.redAccent
                                  : Colors.white38,
                          size: 18),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 68,
                      child: Text(
                        step.$1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDone
                              ? Colors.white70
                              : isCurrent
                                  ? Colors.white
                                  : Colors.white38,
                          fontSize: 9,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 12),

          // Action buttons
          if (!canModify)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.lock_outline, color: Colors.white38, size: 14),
                  SizedBox(width: 6),
                  Text('View-only access — status updates are restricted.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            )
          else if (!isUpdating)
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _actionButtons(context),
            )
          else
            const SizedBox(
              height: 36,
              child: Center(
                child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _actionButtons(BuildContext context) {
    final buttons = <Widget>[];

    void addBtn(String label, String newStatus, Color color, IconData icon) {
      buttons.add(ElevatedButton.icon(
        onPressed: () => _updateStatus(context, newStatus),
        icon: Icon(icon, size: 14),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.2),
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ));
    }

    final s = currentStatus.toLowerCase();
    if (s == 'active' || s == 'pending') {
      addBtn('Verify Incident', 'Verified', Colors.blueAccent, Icons.verified);
    }
    if (s == 'verified') {
      addBtn('Send Ambulance', 'Ambulance Sent', Colors.purpleAccent, Icons.local_hospital);
      addBtn('Notify Police', 'Police Notified', Colors.cyanAccent, Icons.local_police);
    }
    if (s == 'ambulance sent') {
      addBtn('Notify Police', 'Police Notified', Colors.cyanAccent, Icons.local_police);
      addBtn('Resolve', 'Resolved', Colors.greenAccent, Icons.check_circle);
    }
    if (s == 'police notified') {
      addBtn('Resolve', 'Resolved', Colors.greenAccent, Icons.check_circle);
    }
    if (s == 'resolved') {
      buttons.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
            SizedBox(width: 6),
            Text('Incident Resolved',
                style: TextStyle(color: Colors.greenAccent, fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ));
    }

    return buttons;
  }

  Future<void> _updateStatus(BuildContext context, String newStatus) async {
    onUpdating(true);
    try {
      final update = <String, dynamic>{'status': newStatus};
      if (newStatus == 'Resolved') update['endedAt'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance
          .collection('sos_sessions').doc(docId).update(update);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Status → $newStatus'),
          backgroundColor: Colors.green.withValues(alpha: 0.85),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      onUpdating(false);
    }
  }
}

// ─── User Profile Section (fetches from Firestore users collection) ───────────

class _UserProfileSection extends StatelessWidget {
  final String userId;
  final Map<String, dynamic> sessionData;

  const _UserProfileSection({required this.userId, required this.sessionData});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snap) {
        final profile = snap.data?.exists == true
            ? snap.data!.data() as Map<String, dynamic>
            : <String, dynamic>{};

        // Merge session-embedded profile (if any) with Firestore user doc
        final merged = {
          ...sessionData['userProfile'] as Map<String, dynamic>? ?? {},
          ...profile,
        };

        return Column(
          children: [
            // Personal info
            _Section(
              title: 'Patient Information',
              icon: Icons.person_outline,
              iconColor: Colors.blueAccent,
              child: Column(
                children: [
                  _InfoRow(Icons.person, 'Name',
                      merged['name'] ?? merged['displayName'] ?? '—'),
                  _InfoRow(Icons.phone, 'Phone',
                      merged['phone'] ?? merged['phoneNumber'] ?? '—',
                      onTap: () => _call(merged['phone'] ?? merged['phoneNumber'])),
                  _InfoRow(Icons.water_drop, 'Blood Group',
                      merged['bloodGroup'] ?? merged['blood_group'] ?? '—',
                      valueColor: Colors.redAccent),
                  _InfoRow(Icons.medical_information, 'Medical Conditions',
                      merged['medicalConditions'] ?? merged['conditions'] ?? '—'),
                  _InfoRow(Icons.directions_car, 'Vehicle',
                      _vehicleText(merged)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Emergency contacts
            _Section(
              title: 'Emergency Contacts',
              icon: Icons.contact_phone_outlined,
              iconColor: Colors.orangeAccent,
              child: _EmergencyContacts(userId: userId, profile: merged),
            ),
          ],
        );
      },
    );
  }

  String _vehicleText(Map<String, dynamic> p) {
    final make = p['vehicleMake'] ?? p['vehicle_make'] ?? '';
    final model = p['vehicleModel'] ?? p['vehicle_model'] ?? '';
    final plate = p['vehiclePlate'] ?? p['vehicle_plate'] ?? p['licensePlate'] ?? '';
    if (make.isEmpty && model.isEmpty && plate.isEmpty) return '—';
    return [make, model, if (plate.isNotEmpty) '($plate)']
        .where((s) => s.isNotEmpty)
        .join(' ');
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }
}

// ─── Emergency contacts fetched from subcollection ───────────────────────────

class _EmergencyContacts extends StatelessWidget {
  final String userId;
  final Map<String, dynamic> profile;

  const _EmergencyContacts({required this.userId, required this.profile});

  @override
  Widget build(BuildContext context) {
    // Try subcollection first, then fall back to embedded array in profile
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users').doc(userId)
          .collection('emergency_contacts').get(),
      builder: (context, snap) {
        List<Map<String, dynamic>> contacts = [];

        if (snap.data != null && snap.data!.docs.isNotEmpty) {
          contacts = snap.data!.docs
              .map((d) => d.data() as Map<String, dynamic>)
              .toList();
        } else {
          // Fall back to embedded contacts in profile
          final embedded = profile['emergencyContacts'] ?? profile['contacts'];
          if (embedded is List) {
            contacts = embedded.cast<Map<String, dynamic>>();
          }
        }

        if (contacts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No emergency contacts found.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          );
        }

        return Column(
          children: contacts.map((c) {
            final name = c['name'] ?? c['contactName'] ?? 'Unknown';
            final phone = c['phone'] ?? c['phoneNumber'] ?? '—';
            final relation = c['relation'] ?? c['relationship'] ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_outline,
                        color: Colors.orangeAccent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                        if (relation.isNotEmpty)
                          Text(relation, style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (phone != '—')
                    GestureDetector(
                      onTap: () async {
                        final uri = Uri.parse('tel:$phone');
                        if (await canLaunchUrl(uri)) launchUrl(uri);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.call, color: Colors.greenAccent, size: 14),
                            const SizedBox(width: 4),
                            Text(phone,
                                style: const TextStyle(
                                    color: Colors.greenAccent, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ─── Location Section ──────────────────────────────────────────────────────────

class _LocationSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LocationSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final lat = data['lat'] ?? data['latitude'];
    final lng = data['lng'] ?? data['longitude'];
    final address = data['address'] ?? data['location'] ?? '—';

    return _Section(
      title: 'Accident Location',
      icon: Icons.location_on,
      iconColor: Colors.redAccent,
      trailing: (lat != null && lng != null)
          ? TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AccidentMapScreen(sessionData: data),
              )),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Open Map'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blueAccent,
                textStyle: const TextStyle(fontSize: 12),
              ),
            )
          : null,
      child: Column(
        children: [
          if (lat != null && lng != null) ...[
            _InfoRow(Icons.my_location, 'Coordinates',
                '${(lat as num).toStringAsFixed(6)}, ${(lng as num).toStringAsFixed(6)}',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: '$lat, $lng'));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Coordinates copied'),
                    duration: Duration(seconds: 1),
                  ));
                }),
          ],
          if (address != '—') _InfoRow(Icons.place_outlined, 'Address', address),
          if (lat == null && lng == null && address == '—')
            const Text('Location not available.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── Live Tracking Section ─────────────────────────────────────────────────────

class _LiveTrackingSection extends StatelessWidget {
  final String userId;
  final Map<String, dynamic> sessionData;

  const _LiveTrackingSection({required this.userId, required this.sessionData});

  @override
  Widget build(BuildContext context) {
    final trackingSessionId = sessionData['trackingSessionId'] as String?;

    return _Section(
      title: 'Live Tracking',
      icon: Icons.gps_fixed,
      iconColor: Colors.greenAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trackingSessionId != null && trackingSessionId.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text('Tracking session active',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                final url = 'https://crashaid-a1d3c.web.app/track/$trackingSessionId';
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.gps_fixed, size: 16),
              label: const Text('Open Live Tracker'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.withValues(alpha: 0.15),
                foregroundColor: Colors.greenAccent,
                side: const BorderSide(color: Colors.greenAccent, width: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.gps_off, color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                Text(
                  sessionData['endedAt'] != null
                      ? 'Tracking ended with session'
                      : 'No live tracking for this session',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Session metadata ──────────────────────────────────────────────────────────

class _SessionDataSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SessionDataSection({required this.data});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Session Data',
      icon: Icons.info_outline,
      iconColor: Colors.blueAccent,
      child: Column(
        children: [
          _InfoRow(Icons.person, 'User ID', data['userId'] ?? '—'),
          _InfoRow(Icons.tag, 'Session ID', data['sessionId'] ?? '—'),
        ],
      ),
    );
  }
}

class _MetaSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MetaSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : null;
    final endedAt = data['endedAt'] != null
        ? (data['endedAt'] as Timestamp).toDate()
        : null;
    final impactValue = data['impactValue'] ?? data['impact_value'];

    return _Section(
      title: 'Incident Metadata',
      icon: Icons.info_outline,
      iconColor: Colors.white54,
      child: Column(
        children: [
          if (createdAt != null)
            _InfoRow(Icons.access_time, 'Triggered At', _formatDate(createdAt)),
          if (endedAt != null)
            _InfoRow(Icons.check_circle_outline, 'Ended At', _formatDate(endedAt)),
          if (createdAt != null && endedAt != null)
            _InfoRow(Icons.timer_outlined, 'Duration',
                _duration(createdAt, endedAt)),
          if (impactValue != null)
            _InfoRow(Icons.speed, 'Impact Value', '$impactValue g',
                valueColor: _impactColor(impactValue)),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  String _duration(DateTime start, DateTime end) {
    final diff = end.difference(start);
    if (diff.inMinutes < 1) return '${diff.inSeconds}s';
    if (diff.inHours < 1) return '${diff.inMinutes}m ${diff.inSeconds.remainder(60)}s';
    return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
  }

  Color _impactColor(dynamic v) {
    final val = (v as num).toDouble();
    if (val < 2.0) return Colors.greenAccent;
    if (val < 4.0) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}

// ─── Shared widgets ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final Widget? trailing;

  const _Section({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: iconColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3)),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 4),
          const Divider(color: Colors.white12),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  const _InfoRow(this.icon, this.label, this.value,
      {this.valueColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text(
                value,
                style: TextStyle(
                  color: valueColor ?? Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: onTap != null ? TextDecoration.underline : null,
                  decorationColor: valueColor ?? Colors.white54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// PotholeReport
///
/// A single crowd-sourced pothole report pulled from Firestore.
class PotholeReport {
  final String id;
  final double lat;
  final double lng;
  final String severity; // 'Low' | 'Medium' | 'High'
  final String? note;
  final String reportedBy;
  final DateTime? reportedAt;

  PotholeReport({
    required this.id,
    required this.lat,
    required this.lng,
    required this.severity,
    this.note,
    required this.reportedBy,
    this.reportedAt,
  });

  factory PotholeReport.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = data['reportedAt'];
    return PotholeReport(
      id: doc.id,
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
      severity: data['severity'] as String? ?? 'Medium',
      note: data['note'] as String?,
      reportedBy: data['reportedBy'] as String? ?? 'anonymous',
      reportedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// PotholeService
///
/// Writes and reads crowd-sourced pothole reports so nearby drivers
/// (and the admin dashboard, if wired up later) can see them.
///
/// Collection: potholes
/// Document fields:
///   lat, lng, severity, note, reportedBy, reportedAt
class PotholeService {
  static const _collection = 'potholes';

  /// Submits a new pothole report at the given coordinates.
  /// Returns the new document ID on success, null on failure.
  static Future<String?> reportPothole({
    required double lat,
    required double lng,
    required String severity,
    String? note,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'anonymous';

      final docRef = await FirebaseFirestore.instance.collection(_collection).add({
        'lat': lat,
        'lng': lng,
        'severity': severity,
        'note': note,
        'reportedBy': uid,
        'reportedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ PotholeService: report created — ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('🔴 PotholeService: reportPothole failed — $e');
      return null;
    }
  }

  /// One-time fetch of all pothole reports (used to seed the map on load).
  static Future<List<PotholeReport>> fetchAll() async {
    try {
      final snap = await FirebaseFirestore.instance.collection(_collection).get();
      return snap.docs.map((d) => PotholeReport.fromDoc(d)).toList();
    } catch (e) {
      debugPrint('🔴 PotholeService: fetchAll failed — $e');
      return [];
    }
  }

  /// Live stream of pothole reports so the map updates in real time
  /// as other users submit new reports.
  static Stream<List<PotholeReport>> watchAll() {
    return FirebaseFirestore.instance.collection(_collection).snapshots().map(
          (snap) => snap.docs.map((d) => PotholeReport.fromDoc(d)).toList(),
        );
  }
}

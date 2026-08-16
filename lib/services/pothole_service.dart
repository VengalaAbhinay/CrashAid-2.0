import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// PotholeReport
///
/// A single crowd-sourced hazard report pulled from Firestore.
///
/// NOTE: `severity` keeps its original internal values — 'Low' | 'Medium' |
/// 'High' — unchanged, because AmbulanceRoutingService's hazard-penalty
/// lookup keys off these exact strings. Only the *display* label shown to
/// the user (see [severityDisplayLabel]) uses the friendlier
/// Small/Medium/Large-Critical wording from the feature spec.
class PotholeReport {
  final String id;
  final double lat;
  final double lng;
  final String severity; // 'Low' | 'Medium' | 'High' — DO NOT rename values
  final String type; // 'Pothole' | 'Road damage' | 'Dangerous road' | 'Other hazard'
  final String? note;
  final String? photoUrl;
  final String reportedBy;
  final DateTime? reportedAt;
  final int confirmCount;
  final List<String> confirmedBy;

  PotholeReport({
    required this.id,
    required this.lat,
    required this.lng,
    required this.severity,
    this.type = 'Pothole',
    this.note,
    this.photoUrl,
    required this.reportedBy,
    this.reportedAt,
    this.confirmCount = 0,
    this.confirmedBy = const [],
  });

  /// Tolerantly reads a numeric field that might have been written as a
  /// num, a numeric string, or left out entirely by an old/manual test
  /// document — returns null instead of throwing if it can't be read.
  static double? _numOrNull(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  factory PotholeReport.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = data['reportedAt'];

    final lat = _numOrNull(data['lat']);
    final lng = _numOrNull(data['lng']);
    if (lat == null || lng == null) {
      // Deliberately thrown (not silently defaulted to 0,0) so the caller
      // can log + skip just this one document instead of guessing a
      // location for it.
      throw StateError('potholes/${doc.id} has no valid lat/lng');
    }

    return PotholeReport(
      id: doc.id,
      lat: lat,
      lng: lng,
      severity: data['severity'] as String? ?? 'Medium',
      type: data['type'] as String? ?? 'Pothole',
      note: data['note'] as String?,
      photoUrl: data['photoUrl'] as String?,
      reportedBy: data['reportedBy'] as String? ?? 'anonymous',
      reportedAt: ts is Timestamp ? ts.toDate() : null,
      confirmCount: (data['confirmCount'] as num?)?.toInt() ?? 0,
      confirmedBy: (data['confirmedBy'] as List?)?.cast<String>() ?? const [],
    );
  }

  /// User-facing severity label per the feature spec (Small / Medium /
  /// Large-Critical), mapped from the stable internal Low/Medium/High value.
  String get severityDisplayLabel {
    switch (severity) {
      case 'Low':
        return 'Small';
      case 'High':
        return 'Large/Critical';
      default:
        return 'Medium';
    }
  }

  bool confirmedByUser(String uid) => confirmedBy.contains(uid);
}

/// PotholeService
///
/// Writes and reads crowd-sourced hazard reports so nearby drivers, the
/// ambulance-routing feature, and the admin dashboard can all see them.
///
/// Collection: potholes
/// Document fields:
///   lat, lng, severity, type, note, photoUrl, reportedBy, reportedAt,
///   confirmCount, confirmedBy
class PotholeService {
  static const _collection = 'potholes';

  /// Submits a new hazard report.
  ///
  /// Location is captured automatically at submit time via GPS — callers
  /// do not need to (and should not) pass in a stale/cached position, so
  /// every report reflects exactly where the device is right now.
  ///
  /// Returns the new document ID on success, null on failure.
  static Future<String?> reportPothole({
    required String severity,
    String type = 'Pothole',
    String? note,
    File? photo,
  }) async {
    try {
      // Automatic Location — always capture a fresh GPS fix at report time.
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));

      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'anonymous';

      // Pre-generate the doc ID so the photo can be uploaded to a path
      // that matches the report before the Firestore doc is written.
      final docRef = FirebaseFirestore.instance.collection(_collection).doc();

      String? photoUrl;
      if (photo != null) {
        photoUrl = await _uploadPhoto(docRef.id, photo);
      }

      await docRef.set({
        'lat': position.latitude,
        'lng': position.longitude,
        'severity': severity,
        'type': type,
        'note': note,
        'photoUrl': photoUrl,
        'reportedBy': uid,
        'reportedAt': FieldValue.serverTimestamp(),
        'confirmCount': 0,
        'confirmedBy': <String>[],
      });

      debugPrint('✅ PotholeService: report created — ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('🔴 PotholeService: reportPothole failed — $e');
      return null;
    }
  }

  static Future<String?> _uploadPhoto(String docId, File photo) async {
    try {
      final ref = FirebaseStorage.instance.ref().child('potholes/$docId/photo.jpg');
      await ref.putFile(photo);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('🔴 PotholeService: photo upload failed — $e');
      return null;
    }
  }

  /// Crowd Confirmation — "I found this pothole too."
  ///
  /// Adds the current user to the report's confirmedBy list and bumps
  /// confirmCount, atomically and exactly once per user (a transaction
  /// guards against double-counting from double-taps or race conditions).
  ///
  /// Returns true if the confirmation was recorded, false if this user
  /// had already confirmed it (or on error).
  static Future<bool> confirmPothole(String reportId) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'anonymous';

    try {
      final docRef = FirebaseFirestore.instance.collection(_collection).doc(reportId);

      return await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return false;

        final data = snap.data() as Map<String, dynamic>;
        final confirmedBy = (data['confirmedBy'] as List?)?.cast<String>() ?? [];
        if (confirmedBy.contains(uid)) return false; // already confirmed

        tx.update(docRef, {
          'confirmCount': FieldValue.increment(1),
          'confirmedBy': FieldValue.arrayUnion([uid]),
        });
        return true;
      });
    } catch (e) {
      debugPrint('🔴 PotholeService: confirmPothole failed — $e');
      return false;
    }
  }

  /// Converts a batch of documents to reports, skipping (and logging) any
  /// individual document that fails to parse — e.g. a stray manually-added
  /// test document with the wrong field types — instead of letting one bad
  /// document blank out the entire list.
  static List<PotholeReport> _parseDocs(List<QueryDocumentSnapshot> docs) {
    final reports = <PotholeReport>[];
    for (final d in docs) {
      try {
        reports.add(PotholeReport.fromDoc(d));
      } catch (e) {
        debugPrint('🟠 PotholeService: skipping malformed report ${d.id} — $e');
      }
    }
    return reports;
  }

  /// One-time fetch of all pothole reports (used to seed the map on load).
  static Future<List<PotholeReport>> fetchAll() async {
    try {
      final snap = await FirebaseFirestore.instance.collection(_collection).get();
      return _parseDocs(snap.docs);
    } catch (e) {
      debugPrint('🔴 PotholeService: fetchAll failed — $e');
      return [];
    }
  }

  /// Live stream of pothole reports so the map updates in real time
  /// as other users submit new reports or confirm existing ones.
  static Stream<List<PotholeReport>> watchAll() {
    return FirebaseFirestore.instance
        .collection(_collection)
        .snapshots()
        .map((snap) => _parseDocs(snap.docs));
  }
}
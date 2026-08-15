import 'package:cloud_firestore/cloud_firestore.dart';

/// Saves point-in-time analytics snapshots to Firestore so admins can
/// track how key metrics changed over time, triggered by the dashboard's
/// refresh button.
///
/// Snapshots are written to the `analytics_history` collection, one
/// document per refresh, ordered by `capturedAt`.
class AnalyticsSnapshotService {
  final FirebaseFirestore _db;

  AnalyticsSnapshotService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'analytics_history';

  /// Saves a snapshot using counts already computed by the caller.
  ///
  /// Prefer this over [captureSnapshot] when the caller has already done a
  /// server fetch — avoids a redundant Firestore read and ensures the saved
  /// numbers exactly match what the dashboard displayed.
  Future<Map<String, dynamic>> captureSnapshotFromCounts({
    String? capturedBy,
    required int totalUsers,
    required int totalSos,
    required int activeSos,
    required int todaySos,
    Map<String, int>? statusBreakdown,
  }) async {
    final now = DateTime.now();

    final snapshot = {
      'capturedAt':      Timestamp.fromDate(now),
      'capturedBy':      capturedBy,
      'totalUsers':      totalUsers,
      'totalSos':        totalSos,
      'activeSos':       activeSos,
      'todaySos':        todaySos,
      if (statusBreakdown != null) 'statusBreakdown': statusBreakdown,
    };

    await _db.collection(collection).add(snapshot);
    return snapshot;
  }

  /// Computes current stats from Firestore and writes a snapshot document.
  ///
  /// Use this only when you don't already have fresh data in hand.
  /// Prefer [captureSnapshotFromCounts] after a forced server fetch.
  Future<Map<String, dynamic>> captureSnapshot({String? capturedBy}) async {
    final sosSnap   = await _db.collection('sos_sessions').get();
    final usersSnap = await _db.collection('users').get();

    final docs = sosSnap.docs;
    final now  = DateTime.now();

    final totalSos   = docs.length;
    final totalUsers = usersSnap.docs.length;

    final activeSos = docs.where((d) {
      final data   = d.data();
      final status = (data['status'] as String? ?? '').toLowerCase();
      return data['endedAt'] == null &&
          status != 'resolved' &&
          status != 'closed';
    }).length;

    final todaySos = docs.where((d) {
      final data = d.data();
      final ts   = data['createdAt'];
      if (ts == null) return false;
      final dt = (ts as Timestamp).toDate();
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).length;

    // Status breakdown — mirrors the resolution logic used elsewhere.
    final statusCounts = <String, int>{};
    for (final doc in docs) {
      final data   = doc.data();
      final status = (data['status'] as String?)?.trim();
      final key    = status?.isNotEmpty == true
          ? status!
          : (data['endedAt'] == null ? 'Active' : 'Resolved');
      statusCounts[key] = (statusCounts[key] ?? 0) + 1;
    }

    return captureSnapshotFromCounts(
      capturedBy:      capturedBy,
      totalUsers:      totalUsers,
      totalSos:        totalSos,
      activeSos:       activeSos,
      todaySos:        todaySos,
      statusBreakdown: statusCounts,
    );
  }

  /// Stream of past snapshots, most recent first.
  Stream<QuerySnapshot> watchHistory({int limit = 20}) {
    return _db
        .collection(collection)
        .orderBy('capturedAt', descending: true)
        .limit(limit)
        .snapshots();
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// SosFirestoreService
///
/// Writes SOS events to Firestore so the admin dashboard can display them.
/// Call [createSession] when an SOS is triggered and [resolveSession] when
/// the user taps "I'm Safe".
///
/// Collection: sos_sessions
/// Document fields:
///   uid, userName, phone, bloodGroup, medicalCondition,
///   lat, lng, address, status, createdAt, endedAt, sessionId
class SosFirestoreService {
  static const _collection = 'sos_sessions';

  // Holds the current session document ID so we can update / resolve it later.
  static String? _activeDocId;

  /// Creates a new sos_sessions document.
  /// Returns the Firestore document ID on success, null on failure.
  static Future<String?> createSession({
    double? lat,
    double? lng,
    String? address,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'anonymous';
      final prefs = await SharedPreferences.getInstance();

      final name = prefs.getString('name') ?? user?.displayName ?? 'Unknown';
      final phone = prefs.getString('phone') ?? user?.phoneNumber ?? '';
      final blood = prefs.getString('blood') ?? '';
      final condition = prefs.getString('condition') ?? '';
      final allergy = prefs.getString('allergy') ?? '';

      final docRef =
          await FirebaseFirestore.instance.collection(_collection).add({
        'uid': uid,
        'userName': name,
        'phone': phone,
        'bloodGroup': blood,
        'medicalCondition': condition.isNotEmpty ? condition : null,
        'allergy': allergy.isNotEmpty ? allergy : null,
        'lat': lat,
        'lng': lng,
        'address': address,
        'status': 'Active',
        'createdAt': FieldValue.serverTimestamp(),
        'endedAt': null,
        // Also write user profile snapshot so admin details page works offline
        'userProfile': {
          'name': name,
          'phone': phone,
          'bloodGroup': blood,
          'medicalCondition': condition,
          'allergy': allergy,
        },
      });

      _activeDocId = docRef.id;
      debugPrint('✅ SosFirestore: session created — ${docRef.id}');

      // Also upsert the user document so "Total Users" stat works
      await _upsertUser(uid, name, phone);

      return docRef.id;
    } catch (e) {
      debugPrint('🔴 SosFirestore: createSession failed — $e');
      return null;
    }
  }

  /// Marks the active session as Resolved.
  static Future<void> resolveSession() async {
    final id = _activeDocId;
    if (id == null) return;
    try {
      await FirebaseFirestore.instance.collection(_collection).doc(id).update({
        'status': 'Resolved',
        'endedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ SosFirestore: session resolved — $id');
      _activeDocId = null;
    } catch (e) {
      debugPrint('🔴 SosFirestore: resolveSession failed — $e');
    }
  }

  /// Updates status of the active session (e.g. Verified, Ambulance Sent…)
  static Future<void> updateStatus(String status) async {
    final id = _activeDocId;
    if (id == null) return;
    try {
      final update = <String, dynamic>{'status': status};
      if (status == 'Resolved') {
        update['endedAt'] = FieldValue.serverTimestamp();
        _activeDocId = null;
      }
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(id)
          .update(update);
    } catch (e) {
      debugPrint('🔴 SosFirestore: updateStatus failed — $e');
    }
  }

  /// Upserts a minimal user document in the users collection.
  /// Admin dashboard reads this for Total Users count.
  static Future<void> _upsertUser(
      String uid, String name, String phone) async {
    try {
      final ref =
          FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          'name': name,
          'phone': phone,
          'createdAt': FieldValue.serverTimestamp(),
          'uid': uid,
        });
        debugPrint('✅ SosFirestore: user doc created — $uid');
      } else {
        // Update name/phone in case they changed
        await ref.update({'name': name, 'phone': phone});
      }
    } catch (e) {
      debugPrint('🔴 SosFirestore: _upsertUser failed — $e');
    }
  }

  static String? get activeDocId => _activeDocId;
}
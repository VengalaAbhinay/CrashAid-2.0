import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_role.dart';

/// Looks up the admin role assigned to the currently signed-in user.
///
/// Roles are stored in the Firestore collection `admin_users`, where each
/// document is keyed by the user's UID (or, as a fallback, their lowercase
/// email) and has a `role` string field — one of the `kRole*` constants in
/// `admin_roles.dart` (e.g. 'super_admin', 'emergency_operator',
/// 'hospital_coordinator', 'police_coordinator').
///
/// Example document at `admin_users/{uid}`:
/// ```json
/// { "role": "emergency_operator", "email": "operator@crashaid.com" }
/// ```
class RolesService {
  final FirebaseFirestore _db;

  RolesService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static const String _collection = 'admin_users';

  /// Returns the role string for the currently signed-in user, or null if
  /// they are not signed in or have no admin role assigned.
  Future<String?> getCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return getRoleForUser(uid: user.uid, email: user.email);
  }

  /// Returns the role string for a given [uid] / [email], or null if no
  /// admin role is assigned.
  ///
  /// Looks up by UID first (preferred, stable identifier), then falls back
  /// to a lowercase-email-keyed document for convenience when seeding
  /// admin accounts manually.
  Future<String?> getRoleForUser({required String uid, String? email}) async {
    // 1. Primary lookup: admin_users/{uid}
    final byUid = await _db.collection(_collection).doc(uid).get();
    if (byUid.exists) {
      final role = byUid.data()?['role'] as String?;
      if (role != null && role.trim().isNotEmpty) return role.trim();
    }

    // 2. Fallback lookup: admin_users/{lowercase email}
    if (email != null && email.isNotEmpty) {
      final byEmail = await _db
          .collection(_collection)
          .doc(email.toLowerCase().trim())
          .get();
      if (byEmail.exists) {
        final role = byEmail.data()?['role'] as String?;
        if (role != null && role.trim().isNotEmpty) return role.trim();
      }
    }

    return null;
  }

  /// Returns a real-time stream of all documents in the [_collection].
  /// Each document represents one admin user.
  Stream<QuerySnapshot> getAllAdminUsers() =>
      _db.collection(_collection).snapshots();

  /// Creates or updates the admin document for [userId], setting its role
  /// to [role] and marking it as active.
  Future<void> assignRoleToUser(String userId, UserRole role) =>
      _db.collection(_collection).doc(userId).set(
    {
      'role': role.roleString,
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  /// Marks the admin document for [userId] as inactive without deleting it.
  Future<void> deactivateAdminUser(String userId) =>
      _db.collection(_collection).doc(userId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
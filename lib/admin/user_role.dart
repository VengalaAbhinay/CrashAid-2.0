// UserRole enum and RolePermissions used by AdminRolesManagement widget.
// These map to the same Firestore role strings as AdminRole in
// admin_roles.dart so they are interchangeable at the data layer.

enum UserRole {
  superAdmin,
  emergencyOperator,
  hospitalCoordinator,
  policeCoordinator;

  /// Human-readable label shown in the UI.
  String get displayName {
    switch (this) {
      case UserRole.superAdmin:
        return 'Super Admin';
      case UserRole.emergencyOperator:
        return 'Emergency Operator';
      case UserRole.hospitalCoordinator:
        return 'Hospital Coordinator';
      case UserRole.policeCoordinator:
        return 'Police Coordinator';
    }
  }

  /// Short description shown in the role-descriptions card.
  String get description {
    switch (this) {
      case UserRole.superAdmin:
        return 'Full access to all features, including user management, '
            'analytics, and system configuration.';
      case UserRole.emergencyOperator:
        return 'Receives live alerts, verifies incidents, and dispatches '
            'emergency help to the scene.';
      case UserRole.hospitalCoordinator:
        return 'Views patient details and prepares emergency care before '
            'the ambulance arrives.';
      case UserRole.policeCoordinator:
        return 'Views accident locations and manages traffic and safety '
            'response in the area.';
    }
  }

  /// Firestore role string for this value.
  String get roleString {
    switch (this) {
      case UserRole.superAdmin:
        return 'super_admin';
      case UserRole.emergencyOperator:
        return 'emergency_operator';
      case UserRole.hospitalCoordinator:
        return 'hospital_coordinator';
      case UserRole.policeCoordinator:
        return 'police_coordinator';
    }
  }
}

/// Parses a Firestore role string into a [UserRole].
/// Throws [ArgumentError] if [roleString] is unrecognised.
UserRole parseUserRole(String roleString) {
  for (final role in UserRole.values) {
    if (role.roleString == roleString.trim().toLowerCase()) return role;
  }
  throw ArgumentError('Unknown role: $roleString');
}

/// Per-role permission helper used by [AdminRolesManagement].
class RolePermissions {
  final UserRole _role;

  RolePermissions(this._role);

  bool canViewIncidents() => true; // all roles can view

  bool canVerifyIncidents() =>
      _role == UserRole.superAdmin || _role == UserRole.emergencyOperator;

  bool canDispatchHelp() =>
      _role == UserRole.superAdmin || _role == UserRole.emergencyOperator;

  bool canViewPatientDetails() =>
      _role == UserRole.superAdmin || _role == UserRole.hospitalCoordinator;

  bool canModifyEmergencyCare() =>
      _role == UserRole.superAdmin || _role == UserRole.hospitalCoordinator;

  bool canViewAccidentLocations() =>
      _role == UserRole.superAdmin || _role == UserRole.policeCoordinator;

  bool canManageTrafficResponse() =>
      _role == UserRole.superAdmin || _role == UserRole.policeCoordinator;

  bool canViewAnalytics() => _role == UserRole.superAdmin;

  bool canManageUsers() => _role == UserRole.superAdmin;

  bool canManageAdmins() => _role == UserRole.superAdmin;
}
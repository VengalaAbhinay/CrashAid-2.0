

enum AdminRole {
  superAdmin,
  emergencyOperator,
  hospitalCoordinator,
  policeCoordinator,
}

/// Canonical role-id strings stored in Firestore.
const String kRoleSuperAdmin = 'super_admin';
const String kRoleEmergencyOperator = 'emergency_operator';
const String kRoleHospitalCoordinator = 'hospital_coordinator';
const String kRolePoliceCoordinator = 'police_coordinator';

const Map<String, AdminRole> kRoleStringToEnum = {
  kRoleSuperAdmin: AdminRole.superAdmin,
  kRoleEmergencyOperator: AdminRole.emergencyOperator,
  kRoleHospitalCoordinator: AdminRole.hospitalCoordinator,
  kRolePoliceCoordinator: AdminRole.policeCoordinator,
};

/// Converts a Firestore role string to [AdminRole]. Returns null if the
/// string doesn't match a known role (treated as "not an admin").
AdminRole? adminRoleFromString(String? roleId) {
  if (roleId == null) return null;
  return kRoleStringToEnum[roleId.trim().toLowerCase()];
}

/// Identifies the dashboard tabs that exist.
enum AdminTab { liveAlerts, mapView, users, analytics, missingPersons }

/// Per-role permissions.
class RolePermissions {
  final String label;
  final Set<AdminTab> visibleTabs;

  /// Whether this role can modify data (resolve/verify incidents,
  /// dispatch help, edit users, etc.) vs. read-only access.
  final bool canModify;

  /// Whether this role can manage user accounts.
  final bool canManageUsers;

  const RolePermissions({
    required this.label,
    required this.visibleTabs,
    required this.canModify,
    required this.canManageUsers,
  });
}

const Map<AdminRole, RolePermissions> kRolePermissions = {
  // Super Admin — full access to everything.
  AdminRole.superAdmin: RolePermissions(
    label: 'Super Admin',
    visibleTabs: {
      AdminTab.liveAlerts,
      AdminTab.mapView,
      AdminTab.users,
      AdminTab.analytics,
      AdminTab.missingPersons,
    },
    canModify: true,
    canManageUsers: true,
  ),

  // Emergency Operator — receive alerts, verify incidents, dispatch help.
  AdminRole.emergencyOperator: RolePermissions(
    label: 'Emergency Operator',
    visibleTabs: {
      AdminTab.liveAlerts,
      AdminTab.mapView,
    },
    canModify: true,
    canManageUsers: false,
  ),

  // Hospital Coordinator — view patient details & prepare emergency care.
  // Read-only on incident data.
  AdminRole.hospitalCoordinator: RolePermissions(
    label: 'Hospital Coordinator',
    visibleTabs: {
      AdminTab.liveAlerts,
    },
    canModify: false,
    canManageUsers: false,
  ),

  // Police Coordinator — view accident locations & manage traffic/safety
  // response.
  AdminRole.policeCoordinator: RolePermissions(
    label: 'Police Coordinator',
    visibleTabs: {
      AdminTab.mapView,
      AdminTab.missingPersons,
    },
    canModify: true,
    canManageUsers: false,
  ),
};

/// Returns the permission set for [role]. Falls back to the most
/// restrictive role (hospital coordinator) if [role] is somehow
/// unrecognized, rather than granting elevated access.
RolePermissions permissionsFor(AdminRole role) =>
    kRolePermissions[role] ?? kRolePermissions[AdminRole.hospitalCoordinator]!;

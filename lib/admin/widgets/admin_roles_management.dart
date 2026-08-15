import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../roles_service.dart';
import '../user_role.dart';

/// Admin Roles Management Screen (Super Admin only)
class AdminRolesManagement extends StatefulWidget {
  const AdminRolesManagement({super.key});

  @override
  State<AdminRolesManagement> createState() => _AdminRolesManagementState();
}

class _AdminRolesManagementState extends State<AdminRolesManagement> {
  final _rolesService = RolesService();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Roles & Permissions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showAddAdminDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Admin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Role Descriptions ────────────────────────────────────────
          _buildRoleDescriptionsCard(),
          const SizedBox(height: 16),

          // ── Admin Users Table ────────────────────────────────────────
          const Text(
            'Admin Users',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildAdminUsersTable(),
        ],
      ),
    );
  }

  /// Build role descriptions card
  Widget _buildRoleDescriptionsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(color: Colors.white12),
              ),
            ),
            child: const Text(
              'Role Descriptions',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          ...UserRole.values.map((role) => _buildRoleDescriptionTile(role)),
        ],
      ),
    );
  }

  /// Build individual role description tile
  Widget _buildRoleDescriptionTile(UserRole role) {
    final permissions = RolePermissions(role);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getRoleIcon(role), color: _getRoleColor(role), size: 18),
              const SizedBox(width: 8),
              Text(
                role.displayName,
                style: TextStyle(
                  color: _getRoleColor(role),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            role.description,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _getPermissionBadges(permissions),
          ),
        ],
      ),
    );
  }

  /// Get permission badges for a role
  List<Widget> _getPermissionBadges(RolePermissions permissions) {
    final permissionsList = <String>[];

    if (permissions.canViewIncidents()) permissionsList.add('View Incidents');
    if (permissions.canVerifyIncidents()) permissionsList.add('Verify Incidents');
    if (permissions.canDispatchHelp()) permissionsList.add('Dispatch Help');
    if (permissions.canViewPatientDetails()) permissionsList.add('View Patients');
    if (permissions.canModifyEmergencyCare()) permissionsList.add('Modify Care');
    if (permissions.canViewAccidentLocations()) permissionsList.add('View Accidents');
    if (permissions.canManageTrafficResponse()) permissionsList.add('Manage Traffic');
    if (permissions.canViewAnalytics()) permissionsList.add('View Analytics');
    if (permissions.canManageUsers()) permissionsList.add('Manage Users');
    if (permissions.canManageAdmins()) permissionsList.add('Manage Admins');

    return permissionsList
        .map((perm) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                perm,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            ))
        .toList();
  }

  /// Build admin users table
  Widget _buildAdminUsersTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: _rolesService.getAllAdminUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.redAccent),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Text(
                'No admin users found.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(const Color(0xFF0A0A0A)),
              dataRowColor:
                  WidgetStateProperty.all(const Color(0xFF111111)),
              dividerThickness: 0.3,
              columns: const [
                DataColumn(label: Text('Email', style: TextStyle(color: Colors.grey))),
                DataColumn(label: Text('Role', style: TextStyle(color: Colors.grey))),
                DataColumn(label: Text('Status', style: TextStyle(color: Colors.grey))),
                DataColumn(label: Text('Created', style: TextStyle(color: Colors.grey))),
                DataColumn(label: Text('Actions', style: TextStyle(color: Colors.grey))),
              ],
              rows: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final email = data['email'] ?? 'Unknown';
                final roleString = data['role'] ?? 'unassigned';
                final isActive = data['isActive'] as bool? ?? true;
                final createdAt = data['createdAt'] != null
                    ? (data['createdAt'] as Timestamp).toDate()
                    : null;

                UserRole? role;
                try {
                  role = parseUserRole(roleString);
                } catch (e) {
                  role = null;
                }

                return DataRow(
                  cells: [
                    DataCell(Text(
                      email,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    )),
                    DataCell(
                      role != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getRoleColor(role)
                                    .withValues(alpha: 0.15),
                                border: Border.all(
                                  color: _getRoleColor(role)
                                      .withValues(alpha: 0.5),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getRoleIcon(role),
                                    color: _getRoleColor(role),
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    role.displayName,
                                    style: TextStyle(
                                      color: _getRoleColor(role),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const Text(
                              'Unassigned',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.greenAccent.withValues(alpha: 0.15)
                              : Colors.redAccent.withValues(alpha: 0.15),
                          border: Border.all(
                            color: isActive
                                ? Colors.greenAccent.withValues(alpha: 0.5)
                                : Colors.redAccent.withValues(alpha: 0.5),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            color: isActive
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(
                      createdAt != null
                          ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                          : '-',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    )),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 16),
                            color: Colors.blueAccent,
                            onPressed: () =>
                                _showEditRoleDialog(doc.id, roleString),
                            tooltip: 'Edit Role',
                          ),
                          IconButton(
                            icon: Icon(
                              isActive
                                  ? Icons.block
                                  : Icons.check_circle,
                              size: 16,
                            ),
                            color:
                                isActive ? Colors.orangeAccent : Colors.greenAccent,
                            onPressed: () =>
                                _toggleAdminStatus(doc.id, !isActive),
                            tooltip: isActive ? 'Deactivate' : 'Activate',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  /// Show dialog to add new admin
  void _showAddAdminDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const _AddAdminDialog(),
    );
  }

  /// Show dialog to edit role
  void _showEditRoleDialog(String userId, String currentRole) {
    showDialog(
      context: context,
      builder: (ctx) => _EditRoleDialog(userId: userId, currentRole: currentRole),
    );
  }

  /// Toggle admin user status
  Future<void> _toggleAdminStatus(String userId, bool shouldActivate) async {
    try {
      if (shouldActivate) {
        await _rolesService.assignRoleToUser(
          userId,
          UserRole.emergencyOperator,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin user activated')),
        );
      } else {
        await _rolesService.deactivateAdminUser(userId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin user deactivated')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  /// Get role color
  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.superAdmin:
        return Colors.redAccent;
      case UserRole.emergencyOperator:
        return Colors.orangeAccent;
      case UserRole.hospitalCoordinator:
        return Colors.greenAccent;
      case UserRole.policeCoordinator:
        return Colors.blueAccent;
    }
  }

  /// Get role icon
  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.superAdmin:
        return Icons.admin_panel_settings;
      case UserRole.emergencyOperator:
        return Icons.sos;
      case UserRole.hospitalCoordinator:
        return Icons.local_hospital;
      case UserRole.policeCoordinator:
        return Icons.local_police;
    }
  }
}

/// Dialog to add new admin user
class _AddAdminDialog extends StatefulWidget {
  const _AddAdminDialog();

  @override
  State<_AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends State<_AddAdminDialog> {
  final _emailCtrl = TextEditingController();
  UserRole? _selectedRole;
  bool _loading = false;
  String? _error;
  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add Admin User', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Email address',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF111111),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButton<UserRole>(
            value: _selectedRole,
            hint: const Text('Select Role',
                style: TextStyle(color: Colors.white70)),
            dropdownColor: const Color(0xFF1A1A1A),
            isExpanded: true,
            items: UserRole.values
                .map((role) => DropdownMenuItem(
                      value: role,
                      child: Text(
                        role.displayName,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _selectedRole = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _addAdmin,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text('Add'),
        ),
      ],
    );
  }

  Future<void> _addAdmin() async {
    if (_emailCtrl.text.isEmpty || _selectedRole == null) {
      setState(() => _error = 'Please fill all fields');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // In a real app, you would create the user first in Firebase Auth
      // For now, we'll just show a message
      setState(() {
        _error = 'Please create the Firebase Auth account first, then assign role';
      });
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }
}

/// Dialog to edit admin role
class _EditRoleDialog extends StatefulWidget {
  final String userId;
  final String currentRole;

  const _EditRoleDialog({
    required this.userId,
    required this.currentRole,
  });

  @override
  State<_EditRoleDialog> createState() => _EditRoleDialogState();
}

class _EditRoleDialogState extends State<_EditRoleDialog> {
  late UserRole? _selectedRole;
  bool _loading = false;
  final _rolesService = RolesService();

  @override
  void initState() {
    super.initState();
    try {
      _selectedRole = parseUserRole(widget.currentRole);
    } catch (e) {
      _selectedRole = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit Role', style: TextStyle(color: Colors.white)),
      content: DropdownButton<UserRole>(
        value: _selectedRole,
        dropdownColor: const Color(0xFF1A1A1A),
        isExpanded: true,
        items: UserRole.values
            .map((role) => DropdownMenuItem(
                  value: role,
                  child: Text(
                    role.displayName,
                    style: const TextStyle(color: Colors.white),
                  ),
                ))
            .toList(),
        onChanged: (value) => setState(() => _selectedRole = value),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _updateRole,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text('Update'),
        ),
      ],
    );
  }

  Future<void> _updateRole() async {
    if (_selectedRole == null) return;

    setState(() => _loading = true);

    try {
      await _rolesService.assignRoleToUser(widget.userId, _selectedRole!);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
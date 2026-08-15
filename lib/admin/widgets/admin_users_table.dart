import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminUsersTable extends StatelessWidget {
  const AdminUsersTable({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('No users found.',
                style: TextStyle(color: Colors.grey)),
          );
        }

        final docs = snapshot.data!.docs;

        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(const Color(0xFF1A1A1A)),
              dataRowColor:
                  WidgetStateProperty.all(const Color(0xFF111111)),
              dividerThickness: 0.3,
              columns: const [
                DataColumn(
                    label: Text('Name',
                        style: TextStyle(color: Colors.grey))),
                DataColumn(
                    label: Text('Phone',
                        style: TextStyle(color: Colors.grey))),
                DataColumn(
                    label: Text('User ID',
                        style: TextStyle(color: Colors.grey))),
                DataColumn(
                    label: Text('Joined',
                        style: TextStyle(color: Colors.grey))),
              ],
              rows: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final createdAt = data['createdAt'] != null
                    ? (data['createdAt'] as Timestamp).toDate()
                    : null;

                return DataRow(cells: [
                  DataCell(Text(
                    data['name'] ?? data['displayName'] ?? 'Unknown',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500),
                  )),
                  DataCell(Text(
                    data['phone'] ?? data['phoneNumber'] ?? '-',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  )),
                  DataCell(Text(
                    doc.id,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  )),
                  DataCell(Text(
                    createdAt != null ? _formatDate(createdAt) : '-',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  )),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

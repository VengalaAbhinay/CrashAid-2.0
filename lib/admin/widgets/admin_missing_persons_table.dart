import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Shows all missing_persons reports filed from the app, with status
/// management (Active / Found / Closed) for operators who can modify.
class AdminMissingPersonsTable extends StatelessWidget {
  final bool canModify;
  const AdminMissingPersonsTable({super.key, required this.canModify});

  Color _statusColor(String status) => switch (status.toLowerCase()) {
        'found' => Colors.greenAccent,
        'closed' => Colors.white38,
        _ => Colors.redAccent, // Active
      };

  Future<void> _updateStatus(String docId, String newStatus) async {
    await FirebaseFirestore.instance
        .collection('missing_persons')
        .doc(docId)
        .update({
      'status': newStatus,
      if (newStatus != 'Active') 'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('missing_persons')
          .orderBy('reportedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('No missing person reports.',
                style: TextStyle(color: Colors.grey)),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final status = (data['status'] as String?) ?? 'Active';
            final reportedAt = data['reportedAt'] != null
                ? (data['reportedAt'] as Timestamp).toDate()
                : null;
            final photoUrl = data['photoUrl'] as String?;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _statusColor(status).withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: photoUrl != null && photoUrl.isNotEmpty
                        ? Image.network(photoUrl,
                            width: 56, height: 56, fit: BoxFit.cover)
                        : Container(
                            width: 56,
                            height: 56,
                            color: Colors.white12,
                            child: const Icon(Icons.person,
                                color: Colors.white38),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${data['name'] ?? 'Unknown'}  •  ${data['age'] ?? '-'} yrs  •  ${data['gender'] ?? '-'}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(status,
                                  style: TextStyle(
                                      color: _statusColor(status),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(data['description'] ?? '',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('Last seen: ${data['lastSeenLocation'] ?? '-'}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                        Text(
                          'Reporter: ${data['reporterName'] ?? '-'} (${data['reporterRelation'] ?? '-'}) • ${data['reporterContact'] ?? '-'}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                        if (reportedAt != null)
                          Text(
                            'Filed: ${reportedAt.day}/${reportedAt.month}/${reportedAt.year} ${reportedAt.hour}:${reportedAt.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 10),
                          ),
                        if (canModify) const SizedBox(height: 8),
                        if (canModify)
                          Row(
                            children: ['Active', 'Found', 'Closed']
                                .where((s) => s != status)
                                .map((s) => Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8),
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _statusColor(s),
                                          side: BorderSide(
                                              color: _statusColor(s)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 2),
                                        ),
                                        onPressed: () =>
                                            _updateStatus(docs[i].id, s),
                                        child: Text(s,
                                            style: const TextStyle(fontSize: 11)),
                                      ),
                                    ))
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

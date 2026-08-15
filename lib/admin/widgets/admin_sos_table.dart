import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/incident_details_screen.dart';

/// Live SOS alert feed + History with full status filters.
class AdminSosTable extends StatefulWidget {
  final bool canModify;
  const AdminSosTable({super.key, this.canModify = true});

  @override
  State<AdminSosTable> createState() => _AdminSosTableState();
}

class _AdminSosTableState extends State<AdminSosTable>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // History sub-filter
  String _historyFilter = 'All';

  static const _historyFilters = [
    'All',
    'Active',
    'Pending',
    'Verified',
    'Ambulance Sent',
    'Police Notified',
    'Resolved',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Live / History tab bar ────────────────────────────────────
        Container(
          color: const Color(0xFF111111),
          child: TabBar(
            controller: _tabCtrl,
            labelColor: Colors.redAccent,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.redAccent,
            tabs: const [
              Tab(text: '🔴  Live Feed'),
              Tab(text: '📋  History'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _LiveFeedTab(canModify: widget.canModify),
              _HistoryTab(
                filter: _historyFilter,
                onFilterChange: (f) => setState(() => _historyFilter = f),
                filters: _historyFilters,
                canModify: widget.canModify,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Live Feed Tab: only active/unresolved sessions ──────────────────────────

class _LiveFeedTab extends StatelessWidget {
  final bool canModify;
  const _LiveFeedTab({this.canModify = true});

  @override
  Widget build(BuildContext context) {
    // Only fetch sessions that are not yet resolved
    final stream = FirebaseFirestore.instance
        .collection('sos_sessions')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent));
        }

        final allDocs = snapshot.data?.docs ?? [];
        // Live = not resolved and endedAt is null
        final docs = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final status = _resolveStatus(data).toLowerCase();
          return status != 'resolved';
        }).toList();

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    color: Colors.greenAccent, size: 48),
                SizedBox(height: 12),
                Text('No open incidents right now.',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _AlertCard(
            doc: docs[i],
            onTap: () => _openDetails(context, docs[i], canModify),
          ),
        );
      },
    );
  }
}

// ─── History Tab: ALL sessions with per-status filter ────────────────────────

class _HistoryTab extends StatelessWidget {
  final String filter;
  final ValueChanged<String> onFilterChange;
  final List<String> filters;
  final bool canModify;

  const _HistoryTab({
    required this.filter,
    required this.onFilterChange,
    required this.filters,
    this.canModify = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Filter chips ──────────────────────────────────────────────
        Container(
          color: const Color(0xFF111111),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final (chipColor, _) = _statusColors(f);
                final selected = filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected ? Colors.white : Colors.grey,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        )),
                    selected: selected,
                    selectedColor:
                        f == 'All' ? Colors.redAccent : chipColor,
                    backgroundColor: const Color(0xFF1A1A1A),
                    side: BorderSide(
                      color: selected
                          ? (f == 'All' ? Colors.redAccent : chipColor)
                          : Colors.white12,
                    ),
                    onSelected: (_) => onFilterChange(f),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ── List ──────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('sos_sessions')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child:
                        CircularProgressIndicator(color: Colors.redAccent));
              }

              var docs = snapshot.data?.docs ?? [];

              // ── Key fix: use _resolveStatus consistently ─────────────
              if (filter != 'All') {
                docs = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return _resolveStatus(data).toLowerCase() ==
                      filter.toLowerCase();
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        filter == 'All'
                            ? 'No SOS sessions found.'
                            : filter == 'Active'
                                ? 'No sessions with status "Active".\nOther open statuses exist — try "All" or check Live Feed.'
                                : 'No "$filter" incidents.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, height: 1.5),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  // Count banner
                  Container(
                    color: const Color(0xFF111111),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Text(
                          '${docs.length} record${docs.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) => _AlertCard(
                        doc: docs[i],
                        onTap: () => _openDetails(context, docs[i], canModify),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

/// THE key fix: always read `status` field first; only fall back when absent.
String _resolveStatus(Map<String, dynamic> data) {
  final status = (data['status'] as String?)?.trim() ?? '';
  if (status.isNotEmpty) return status;
  // No status field → infer from endedAt
  return data['endedAt'] == null ? 'Active' : 'Resolved';
}

void _openDetails(BuildContext context, QueryDocumentSnapshot doc,
    [bool canModify = true]) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => IncidentDetailsScreen(sessionDoc: doc, canModify: canModify),
    ),
  );
}

(Color, Color) _statusColors(String status) {
  return switch (status.toLowerCase()) {
    'active' => (
        Colors.redAccent,
        Colors.redAccent.withValues(alpha: 0.15)
      ),
    'pending' => (
        Colors.orangeAccent,
        Colors.orangeAccent.withValues(alpha: 0.15)
      ),
    'verified' => (
        Colors.blueAccent,
        Colors.blueAccent.withValues(alpha: 0.15)
      ),
    'ambulance sent' => (
        Colors.purpleAccent,
        Colors.purpleAccent.withValues(alpha: 0.15)
      ),
    'police notified' => (
        Colors.cyanAccent,
        Colors.cyanAccent.withValues(alpha: 0.15)
      ),
    'resolved' => (
        Colors.greenAccent,
        Colors.greenAccent.withValues(alpha: 0.15)
      ),
    _ => (Colors.grey, Colors.grey.withValues(alpha: 0.15)),
  };
}

// ─── Alert Card ───────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final VoidCallback onTap;

  const _AlertCard({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final status = _resolveStatus(data);
    final isActive = status.toLowerCase() != 'resolved';
    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : null;

    final profile =
        data['userProfile'] as Map<String, dynamic>? ?? {};
    final userName = profile['name'] ??
        profile['displayName'] ??
        data['userName'] ??
        'Unknown User';
    final phone = profile['phone'] ??
        profile['phoneNumber'] ??
        data['phone'] ??
        '—';
    final address = data['address'] ?? data['location'] ?? '—';
    final lat = data['lat'] ?? data['latitude'];
    final lng = data['lng'] ?? data['longitude'];
    final locationText = (lat != null && lng != null)
        ? '${(lat as num).toStringAsFixed(4)}, ${(lng as num).toStringAsFixed(4)}'
        : address;

    final (statusColor, statusBg) = _statusColors(status);

    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? Colors.redAccent.withValues(alpha: 0.4)
                  : Colors.white12,
              width: isActive ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status + time row
              Row(
                children: [
                  if (isActive) ...[
                    _PulseDot(),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (createdAt != null)
                    Text(
                      _timeAgo(createdAt),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12),
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right,
                      color: Colors.white38, size: 18),
                ],
              ),
              const SizedBox(height: 12),
              // User + location row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          Colors.redAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person,
                        color: Colors.redAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            )),
                        if (phone != '—') ...[
                          const SizedBox(height: 2),
                          Text(phone,
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                  if (locationText != '—')
                    Container(
                      constraints:
                          const BoxConstraints(maxWidth: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.blue
                                .withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.blueAccent, size: 12),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              locationText,
                              style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              // Quick actions
              if (isActive) ...[
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 10),
                _QuickActions(
                    docId: doc.id, currentStatus: status),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Pulse dot ────────────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
              color: Colors.redAccent, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

// ─── Quick action buttons ─────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final String docId;
  final String currentStatus;

  const _QuickActions(
      {required this.docId, required this.currentStatus});

  @override
  Widget build(BuildContext context) {
    final actions = _nextActions(currentStatus);
    if (actions.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      children: actions
          .map((a) => SizedBox(
                height: 30,
                child: ElevatedButton(
                  onPressed: () => _updateStatus(context, a.status),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        a.color.withValues(alpha: 0.2),
                    foregroundColor: a.color,
                    side: BorderSide(
                        color: a.color.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  child: Text(a.label),
                ),
              ))
          .toList(),
    );
  }

  List<_Action> _nextActions(String status) {
    return switch (status.toLowerCase()) {
      'active' || 'pending' => [
          _Action('Verify', 'Verified', Colors.blueAccent),
        ],
      'verified' => [
          _Action('Send Ambulance', 'Ambulance Sent',
              Colors.purpleAccent),
          _Action('Notify Police', 'Police Notified',
              Colors.cyanAccent),
        ],
      'ambulance sent' => [
          _Action('Notify Police', 'Police Notified',
              Colors.cyanAccent),
          _Action('Resolve', 'Resolved', Colors.greenAccent),
        ],
      'police notified' => [
          _Action('Resolve', 'Resolved', Colors.greenAccent),
        ],
      _ => [],
    };
  }

  Future<void> _updateStatus(
      BuildContext context, String newStatus) async {
    try {
      final update = <String, dynamic>{'status': newStatus};
      if (newStatus == 'Resolved') {
        update['endedAt'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance
          .collection('sos_sessions')
          .doc(docId)
          .update(update);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Status updated → $newStatus'),
          backgroundColor:
              Colors.green.withValues(alpha: 0.8),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor:
              Colors.redAccent.withValues(alpha: 0.8),
        ));
      }
    }
  }
}

class _Action {
  final String label;
  final String status;
  final Color color;
  const _Action(this.label, this.status, this.color);
}
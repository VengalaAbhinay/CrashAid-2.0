import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../widgets/admin_stat_card.dart';
import '../widgets/admin_sos_table.dart';
import '../widgets/admin_users_table.dart';
import '../widgets/admin_missing_persons_table.dart';
import '../admin_roles.dart';
import '../analytics_snapshot_service.dart';
import 'accident_map_screen.dart';
import '../../auth/login_screen.dart';

// ─── Shared helper: "is this SOS still open?" ────────────────────────────────
// Definition: NOT resolved/closed — same as the Live Feed tab filter.
// This means Pending, Verified, Ambulance Sent, Police Notified all count as
// "open", which is why the stat card is labelled "Open SOS" not "Active SOS".
bool _isSosActive(Map<String, dynamic> data) {
  final status = (data['status'] as String? ?? '').toLowerCase();
  // Explicit resolution always wins, even if endedAt was never set
  if (status == 'resolved' || status == 'closed') return false;
  // No explicit resolution → open only if endedAt is also absent
  return data['endedAt'] == null;
}

class AdminDashboardScreen extends StatefulWidget {
  /// Role id string as stored in Firestore (see admin_roles.dart for the
  /// `kRole*` constants), e.g. 'super_admin', 'emergency_operator',
  /// 'hospital_coordinator', 'police_coordinator'.
  final String userRole;

  const AdminDashboardScreen({super.key, required this.userRole});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTab = 0;

  /// Falls back to the most restrictive role if the stored string doesn't
  /// match a known role, rather than granting elevated access.
  late final AdminRole _role =
      adminRoleFromString(widget.userRole) ?? AdminRole.hospitalCoordinator;

  late final RolePermissions _perms = permissionsFor(_role);

  bool _refreshing = false;

  // Incremented on each manual refresh — passed as a *property* (not as a
  // widget key) to _StatsRowFlash so the StreamBuilders are never rebuilt.
  int _refreshPulseKey = 0;

  Future<void> _handleRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      // Force a server round-trip so the live StreamBuilders below pick up
      // the latest data immediately (instead of relying on local cache).
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('sos_sessions')
            .get(const GetOptions(source: Source.server)),
        FirebaseFirestore.instance
            .collection('users')
            .get(const GetOptions(source: Source.server)),
      ]);

      final sosSnap   = results[0];
      final usersSnap = results[1];
      final now       = DateTime.now();

      // Reuse the already-fetched data so captureSnapshot doesn't fire a
      // second read milliseconds later (avoids double-counting risk).
      final activeSos = sosSnap.docs.where((d) {
        return _isSosActive(d.data());
      }).length;

      final todaySos = sosSnap.docs.where((d) {
        final data = d.data();
        final ts   = data['createdAt'];
        if (ts == null) return false;
        final dt = (ts as Timestamp).toDate();
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      }).length;

      await AnalyticsSnapshotService().captureSnapshotFromCounts(
        capturedBy: FirebaseAuth.instance.currentUser?.email,
        totalUsers: usersSnap.docs.length,
        totalSos:   sosSnap.docs.length,
        activeSos:  activeSos,
        todaySos:   todaySos,
      );

      if (mounted) {
        setState(() => _refreshPulseKey++);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dashboard refreshed — snapshot saved to analytics history.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Ordered list of (tab id, label, content builder) filtered by role.
  late final List<(AdminTab, String, Widget Function())> _tabs = [
    (AdminTab.liveAlerts, '🚨 Live Alerts',
        () => AdminSosTable(canModify: _perms.canModify)),
    (AdminTab.mapView, '🗺️ Map View',
        () => AccidentMapScreen(showAll: true)),
    (AdminTab.users, '👤 Users',
        () => const AdminUsersTable()),
    (AdminTab.analytics, '📊 Analytics',
        () => const _AnalyticsTab()),
    (AdminTab.missingPersons, '🧍 Missing Persons',
        () => AdminMissingPersonsTable(canModify: _perms.canModify)),
  ].where((t) => _perms.visibleTabs.contains(t.$1)).toList();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 480;

    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 380;
            return Row(
              children: [
                const Icon(Icons.local_hospital, color: Colors.redAccent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    narrow ? 'CrashAid' : 'CrashAid Admin',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                _LiveBadge(),
                if (!narrow) const SizedBox(width: 8),
                if (!narrow) _RoleBadge(label: _perms.label),
              ],
            );
          },
        ),
        actions: [
          if (user != null && !isNarrow)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(user.email ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ),
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.redAccent, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, color: Colors.grey),
            tooltip: 'Refresh data & save snapshot',
            onPressed: _refreshing ? null : _handleRefresh,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            tooltip: 'Sign Out',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Text('Sign Out',
                      style: TextStyle(color: Colors.white)),
                  content: const Text('Are you sure you want to sign out?',
                      style: TextStyle(color: Colors.grey)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Stat Cards Row ──────────────────────────────────────────
          // NOTE: _StatsRowFlash receives pulseKey as a *property*, NOT as
          // the widget key. This keeps the StreamBuilders inside _buildStatsRow
          // alive across refreshes so they never lose their live subscription.
          _StatsRowFlash(
            pulseKey: _refreshPulseKey,
            child: _buildStatsRow(),
          ),

          // ── Tab Bar ──────────────────────────────────────────────────
          Container(
            color: const Color(0xFF1A1A1A),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _tabs.length; i++)
                    _tabButton(_tabs[i].$2, i),
                ],
              ),
            ),
          ),

          // ── Tab Content ───────────────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                for (final tab in _tabs) tab.$3(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sos_sessions').snapshots(),
      builder: (context, sosSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, usersSnap) {
            return StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance.ref('live_tracking').onValue,
              builder: (context, rtdbSnap) {

                // Show a skeleton while waiting for the first Firestore event
                if (!sosSnap.hasData || !usersSnap.hasData) {
                  return const _StatsShimmer();
                }

                // ── Firestore stats ─────────────────────────────────────────
                final totalSos   = sosSnap.data!.docs.length;
                final totalUsers = usersSnap.data!.docs.length;

                final fsActive = sosSnap.data!.docs.where((d) {
                  return _isSosActive(d.data() as Map<String, dynamic>);
                }).length;

                final now = DateTime.now();
                final todaySos = sosSnap.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final ts   = data['createdAt'];
                  if (ts == null) return false;
                  final dt = (ts as Timestamp).toDate();
                  return dt.year == now.year &&
                      dt.month == now.month &&
                      dt.day == now.day;
                }).length;

                // ── Realtime DB fallback (active sessions) ──────────────────
                int rtdbActive = 0;
                int rtdbTotal  = 0;
                if (rtdbSnap.hasData &&
                    rtdbSnap.data!.snapshot.value != null) {
                  // Safe cast — guard against unexpected non-Map values
                  final raw = rtdbSnap.data!.snapshot.value;
                  if (raw is Map) {
                    final map = raw;
                    for (final v in map.values) {
                      if (v is Map) {
                        rtdbTotal++;
                        if (v['active'] == true) rtdbActive++;
                      }
                    }
                  }
                }

                // Prefer Firestore; fall back to RTDB if Firestore is empty
                final activeSos    = fsActive > 0 ? fsActive : rtdbActive;
                final displayTotal = totalSos > 0 ? totalSos : rtdbTotal;

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ResponsiveStatsGrid(
                    children: [
                      AdminStatCard(
                        title: 'Total Users',
                        value: '$totalUsers',
                        icon: Icons.people,
                        color: Colors.blueAccent,
                      ),
                      AdminStatCard(
                        title: 'Total SOS',
                        value: '$displayTotal',
                        icon: Icons.sos,
                        color: Colors.orangeAccent,
                      ),
                      AdminStatCard(
                        title: 'Open SOS',
                        value: '$activeSos',
                        icon: Icons.warning_rounded,
                        color: Colors.redAccent,
                        pulse: activeSos > 0,
                      ),
                      AdminStatCard(
                        title: "Today's SOS",
                        value: '$todaySos',
                        icon: Icons.today,
                        color: Colors.greenAccent,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? Colors.redAccent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Stats shimmer skeleton ────────────────────────────────────────────────────

class _StatsShimmer extends StatelessWidget {
  const _StatsShimmer();

  static Widget _shimmerBox() {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: const Center(
        child: SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(
            color: Colors.white24, strokeWidth: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _ResponsiveStatsGrid(
        children: List.generate(4, (i) => _shimmerBox()),
      ),
    );
  }
}

// ─── Responsive stats grid ─────────────────────────────────────────────────────
//
// Lays out the four admin stat cards in a single row on wider screens
// (tablets/laptops/desktop), and as a 2x2 grid on narrow phone-sized
// screens so card content doesn't get squeezed and overflow.
class _ResponsiveStatsGrid extends StatelessWidget {
  final List<Widget> children;
  const _ResponsiveStatsGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Desktop/tablet: single row. Phone (<500px): 2x2 grid.
        if (constraints.maxWidth >= 500) {
          return Row(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                Expanded(child: children[i]),
                if (i < children.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }
        // Phone: 2x2 grid
        final rows = <Widget>[];
        for (int i = 0; i < children.length; i += 2) {
          final hasSecond = i + 1 < children.length;
          rows.add(Row(
            children: [
              Expanded(child: children[i]),
              if (hasSecond) const SizedBox(width: 12),
              if (hasSecond) Expanded(child: children[i + 1]),
            ],
          ));
          if (i + 2 < children.length) rows.add(const SizedBox(height: 12));
        }
        return Column(children: rows);
      },
    );
  }
}

// ─── Live pulse badge ─────────────────────────────────────────────────────────

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: Colors.redAccent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              const Text('LIVE',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Stats row refresh flash ───────────────────────────────────────────────────

/// Briefly highlights the stat-cards row when [pulseKey] changes (i.e. after a
/// manual refresh). Uses a *property* rather than the widget key so the
/// StreamBuilders inside the child are never destroyed and resubscribed.
class _StatsRowFlash extends StatefulWidget {
  final Widget child;
  final int pulseKey;

  const _StatsRowFlash({required this.child, required this.pulseKey});

  @override
  State<_StatsRowFlash> createState() => _StatsRowFlashState();
}

class _StatsRowFlashState extends State<_StatsRowFlash>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void didUpdateWidget(_StatsRowFlash old) {
    super.didUpdateWidget(old);
    // Re-trigger the flash animation whenever the parent increments pulseKey
    if (widget.pulseKey != old.pulseKey) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final glow = 1 - _ctrl.value; // starts bright, fades out
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.redAccent.withValues(alpha: 0.4 * glow),
              width: 1.5,
            ),
            boxShadow: glow > 0
                ? [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.15 * glow),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─── Role badge ───────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final String label;
  const _RoleBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

// ─── Analytics Tab ────────────────────────────────────────────────────────────

class _AnalyticsTab extends StatelessWidget {
  const _AnalyticsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sos_sessions').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final now = DateTime.now();

        // Use the shared helper so active counts match the dashboard cards
        final total    = docs.length;
        final active   = docs.where((d) => _isSosActive(d.data() as Map<String, dynamic>)).length;

        final resolved = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final s    = (data['status'] as String? ?? '').toLowerCase();
          return s == 'resolved' || s == 'closed' || data['endedAt'] != null;
        }).length;

        final pending = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final s    = (data['status'] as String? ?? '').toLowerCase();
          return s == 'pending';
        }).length;

        // Last 7 days
        final last7 = List.generate(7, (i) {
          final day   = now.subtract(Duration(days: 6 - i));
          final count = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final ts   = data['createdAt'];
            if (ts == null) return false;
            final dt = (ts as Timestamp).toDate();
            return dt.year == day.year &&
                dt.month == day.month &&
                dt.day == day.day;
          }).length;
          return (day, count);
        });

        // Status breakdown
        final statusMap = <String, int>{};
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final s    = data['status'] as String? ??
              (data['endedAt'] == null ? 'Active' : 'Resolved');
          statusMap[s] = (statusMap[s] ?? 0) + 1;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Summary cards row ─────────────────────────────────
              Row(
                children: [
                  _AnalyticsCard('Total Alerts', '$total',
                      Icons.notifications, Colors.orangeAccent),
                  const SizedBox(width: 12),
                  _AnalyticsCard('Pending', '$pending',
                      Icons.hourglass_empty, Colors.orangeAccent),
                  const SizedBox(width: 12),
                  _AnalyticsCard('Active', '$active',
                      Icons.warning_rounded, Colors.redAccent),
                  const SizedBox(width: 12),
                  _AnalyticsCard('Resolved', '$resolved',
                      Icons.check_circle_outline, Colors.greenAccent),
                ],
              ),
              const SizedBox(height: 24),

              // ── Last 7 days bar chart ──────────────────────────────
              _SectionHeader('Daily Incidents (Last 7 Days)'),
              const SizedBox(height: 12),
              _BarChart(data: last7),
              const SizedBox(height: 24),

              // ── Status breakdown ───────────────────────────────────
              _SectionHeader('Status Breakdown'),
              const SizedBox(height: 12),
              ...statusMap.entries.map((e) =>
                  _StatusBar(label: e.key, count: e.value, total: total)),
              const SizedBox(height: 24),

              // ── Snapshot history (from manual refreshes) ───────────
              _SectionHeader('Snapshot History (from Refresh)'),
              const SizedBox(height: 4),
              const Text(
                'Each tap of the refresh button saves a point-in-time snapshot here.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 12),
              const _SnapshotHistory(),
            ],
          ),
        );
      },
    );
  }
}

// ─── Snapshot History ──────────────────────────────────────────────────────────

class _SnapshotHistory extends StatelessWidget {
  const _SnapshotHistory();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: AnalyticsSnapshotService().watchHistory(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(
                  color: Colors.redAccent, strokeWidth: 2),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'No snapshots yet. Tap the refresh button in the top bar to save one.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < docs.length; i++) ...[
                if (i > 0) const Divider(color: Colors.white12, height: 1),
                _SnapshotRow(
                    data: docs[i].data() as Map<String, dynamic>),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SnapshotRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final ts = data['capturedAt'];
    final dt = ts is Timestamp ? ts.toDate() : null;
    final timeLabel = dt == null
        ? '—'
        : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    final capturedBy = data['capturedBy'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.history, color: Colors.white38, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(timeLabel,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (capturedBy != null)
                  Text('by $capturedBy',
                      style: const TextStyle(color: Colors.white24, fontSize: 10)),
              ],
            ),
          ),
          _SnapshotStat('Users', data['totalUsers']),
          const SizedBox(width: 12),
          _SnapshotStat('SOS', data['totalSos']),
          const SizedBox(width: 12),
          _SnapshotStat('Active', data['activeSos'], color: Colors.redAccent),
          const SizedBox(width: 12),
          _SnapshotStat('Today', data['todaySos'], color: Colors.greenAccent),
        ],
      ),
    );
  }
}

class _SnapshotStat extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;
  const _SnapshotStat(this.label, this.value, {this.color = Colors.white70});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('$value',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 9)),
      ],
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _AnalyticsCard(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 28, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(
          color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold));
}

class _BarChart extends StatelessWidget {
  final List<(DateTime, int)> data;
  const _BarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxVal    = data.map((d) => d.$2).fold(0, (a, b) => a > b ? a : b);
    const maxHeight = 100.0;
    final days      = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((d) {
          final barHeight =
              maxVal == 0 ? 4.0 : (d.$2 / maxVal) * maxHeight + 4;
          final dayName = days[d.$1.weekday - 1];
          final isToday = d.$1.day == DateTime.now().day &&
              d.$1.month == DateTime.now().month;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (d.$2 > 0)
                    Text('${d.$2}',
                        style: TextStyle(
                            color: isToday ? Colors.redAccent : Colors.white54,
                            fontSize: 11)),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: isToday
                          ? Colors.redAccent
                          : Colors.redAccent.withValues(alpha: 0.4),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(dayName,
                      style: TextStyle(
                          color: isToday ? Colors.white : Colors.white38,
                          fontSize: 11,
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.normal)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;

  const _StatusBar(
      {required this.label, required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct   = total == 0 ? 0.0 : count / total;
    final color = _color(label);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Expanded(
            child: Stack(children: [
              Container(
                  height: 8,
                  decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(4))),
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4))),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Text('$count',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Color _color(String s) => switch (s.toLowerCase()) {
        'active'          => Colors.redAccent,
        'pending'         => Colors.orangeAccent,
        'verified'        => Colors.blueAccent,
        'ambulance sent'  => Colors.purpleAccent,
        'police notified' => Colors.cyanAccent,
        'resolved'        => Colors.greenAccent,
        _                 => Colors.grey,
      };
}
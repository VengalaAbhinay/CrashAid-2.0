import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'incident_details_screen.dart';

/// Paginated incident history with:
///  • Today / Week / Month / All date filters
///  • Free-text search (name, phone, location)
///  • Response-time column (createdAt → resolvedAt delta)
///  • Tap → IncidentDetailsScreen
///
/// Pass [standalone] = true when navigating to it directly (adds Scaffold+AppBar).
/// Default is false so it embeds cleanly inside the dashboard IndexedStack.
class IncidentHistoryScreen extends StatefulWidget {
  final bool standalone;
  const IncidentHistoryScreen({super.key, this.standalone = false});

  @override
  State<IncidentHistoryScreen> createState() => _IncidentHistoryScreenState();
}

class _IncidentHistoryScreenState extends State<IncidentHistoryScreen> {
  // ── Filter state ─────────────────────────────────────────────────────────
  _DateRange _dateRange = _DateRange.week;
  String _statusFilter = 'All';
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchText = '';

  // ── Pagination ────────────────────────────────────────────────────────────
  static const int _pageSize = 20;
  final List<QueryDocumentSnapshot> _docs = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  bool _initialLoad = true;

  // ── Stream subscription for live page-1 updates ───────────────────────────
  Stream<QuerySnapshot>? _liveStream;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchText = _searchCtrl.text.trim().toLowerCase());
    });
    _startLiveStream();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Rebuild stream whenever date / status filter changes ──────────────────
  void _startLiveStream() {
    setState(() {
      _docs.clear();
      _lastDoc = null;
      _hasMore = true;
      _initialLoad = true;
    });

    Query q = FirebaseFirestore.instance
        .collection('sos_sessions')
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    // Date filter
    final cutoff = _dateRange.cutoff;
    if (cutoff != null) {
      q = q.where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff));
    }

    // Status filter (Firestore-side for All / specific statuses)
    if (_statusFilter != 'All') {
      q = q.where('status', isEqualTo: _statusFilter);
    }

    _liveStream = q.snapshots();
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    Query q = FirebaseFirestore.instance
        .collection('sos_sessions')
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    final cutoff = _dateRange.cutoff;
    if (cutoff != null) {
      q = q.where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff));
    }
    if (_statusFilter != 'All') {
      q = q.where('status', isEqualTo: _statusFilter);
    }
    if (_lastDoc != null) {
      q = q.startAfterDocument(_lastDoc!);
    }

    final snap = await q.get();
    if (!mounted) return;

    if (snap.docs.isEmpty) {
      setState(() {
        _hasMore = false;
        _loading = false;
      });
      return;
    }

    setState(() {
      _docs.addAll(snap.docs);
      _lastDoc = snap.docs.last;
      _hasMore = snap.docs.length == _pageSize;
      _loading = false;
    });
  }

  // ── Client-side search applied on top of server docs ─────────────────────
  List<QueryDocumentSnapshot> _applySearch(List<QueryDocumentSnapshot> docs) {
    if (_searchText.isEmpty) return docs;
    return docs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final profile = d['userProfile'] as Map<String, dynamic>? ?? {};
      final name = (profile['name'] ?? profile['displayName'] ?? d['userName'] ?? '')
          .toString()
          .toLowerCase();
      final phone = (profile['phone'] ?? profile['phoneNumber'] ?? d['phone'] ?? '')
          .toString()
          .toLowerCase();
      final location =
          (d['address'] ?? d['location'] ?? '').toString().toLowerCase();
      final lat = (d['lat'] ?? d['latitude'] ?? '').toString();
      final lng = (d['lng'] ?? d['longitude'] ?? '').toString();

      return name.contains(_searchText) ||
          phone.contains(_searchText) ||
          location.contains(_searchText) ||
          lat.contains(_searchText) ||
          lng.contains(_searchText);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _buildSearchBar(),
        _buildFilterRow(),
        Expanded(child: _buildContent()),
      ],
    );

    if (widget.standalone) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            '📋 Incident History',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: body,
      );
    }
    return body;
  }

  // ── Search bar ────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search by name, phone, location…',
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
          suffixIcon: _searchText.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                  onPressed: () => _searchCtrl.clear(),
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1),
          ),
        ),
      ),
    );
  }

  // ── Filter row: date toggles + status chips ───────────────────────────────
  Widget _buildFilterRow() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range toggle
          Row(
            children: _DateRange.values.map((r) {
              final selected = _dateRange == r;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(r.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.black : Colors.grey,
                      )),
                  selected: selected,
                  selectedColor: Colors.redAccent,
                  backgroundColor: const Color(0xFF1A1A1A),
                  side: BorderSide(
                      color: selected ? Colors.redAccent : Colors.white12),
                  onSelected: (_) {
                    setState(() => _dateRange = r);
                    _startLiveStream();
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Status chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'All',
                'Active',
                'Pending',
                'Verified',
                'Ambulance Sent',
                'Police Notified',
                'Resolved',
              ].map((s) {
                final selected = _statusFilter == s;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s,
                        style: TextStyle(
                          fontSize: 11,
                          color: selected ? Colors.black : Colors.grey,
                        )),
                    selected: selected,
                    selectedColor: _statusChipColor(s),
                    backgroundColor: const Color(0xFF1A1A1A),
                    side: BorderSide(
                        color: selected
                            ? _statusChipColor(s)
                            : Colors.white12),
                    onSelected: (_) {
                      setState(() => _statusFilter = s);
                      _startLiveStream();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusChipColor(String s) => switch (s.toLowerCase()) {
        'active' => Colors.redAccent,
        'pending' => Colors.orangeAccent,
        'verified' => Colors.blueAccent,
        'ambulance sent' => Colors.purpleAccent,
        'police notified' => Colors.cyanAccent,
        'resolved' => Colors.greenAccent,
        _ => Colors.grey,
      };

  // ── Main content ──────────────────────────────────────────────────────────
  Widget _buildContent() {
    return StreamBuilder<QuerySnapshot>(
      stream: _liveStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && _initialLoad) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent));
        }

        // Merge live first page with any paginated pages
        final liveDocs = snap.data?.docs ?? [];
        if (liveDocs.isNotEmpty && _initialLoad) {
          _initialLoad = false;
        }

        // Union: live first page ∪ paginated extras (dedup by id)
        final Map<String, QueryDocumentSnapshot> merged = {};
        for (final d in liveDocs) {
          merged[d.id] = d;
        }
        for (final d in _docs) {
          merged.putIfAbsent(d.id, () => d);
        }
        final allDocs = merged.values.toList()
          ..sort((a, b) {
            final at = (a.data() as Map)['createdAt'];
            final bt = (b.data() as Map)['createdAt'];
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return (bt as Timestamp).compareTo(at as Timestamp);
          });

        final filtered = _applySearch(allDocs);

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history_toggle_off,
                    color: Colors.white24, size: 48),
                const SizedBox(height: 12),
                Text(
                  _searchText.isNotEmpty
                      ? 'No results for "$_searchText"'
                      : 'No incidents in this period',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollEndNotification &&
                n.metrics.extentAfter < 200 &&
                _hasMore) {
              _loadNextPage();
            }
            return false;
          },
          child: Column(
            children: [
              // ── Summary bar ──────────────────────────────────────────
              _SummaryBar(
                  total: filtered.length,
                  hasMore: _hasMore,
                  dateRange: _dateRange),
              // ── Table header ─────────────────────────────────────────
              _TableHeader(),
              // ── Rows ─────────────────────────────────────────────────
              Expanded(
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    if (i == filtered.length) {
                      return _loading
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.redAccent, strokeWidth: 2)),
                            )
                          : TextButton(
                              onPressed: _loadNextPage,
                              child: const Text('Load more',
                                  style: TextStyle(color: Colors.redAccent)),
                            );
                    }
                    return _HistoryRow(
                      doc: filtered[i],
                      index: i,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Summary bar ──────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final int total;
  final bool hasMore;
  final _DateRange dateRange;

  const _SummaryBar(
      {required this.total,
      required this.hasMore,
      required this.dateRange});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F0F0F),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            hasMore ? '$total+ incidents' : '$total incident${total == 1 ? '' : 's'}',
            style:
                const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const Spacer(),
          Text(
            dateRange.label,
            style: const TextStyle(
                color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── Table header ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          SizedBox(width: 28), // index
          Expanded(
              flex: 3,
              child: Text('User',
                  style: _headerStyle)),
          Expanded(
              flex: 2,
              child: Text('Location',
                  style: _headerStyle)),
          Expanded(
              flex: 2,
              child: Text('Date & Time',
                  style: _headerStyle)),
          Expanded(
              flex: 2,
              child: Text('Status',
                  style: _headerStyle)),
          Expanded(
              flex: 2,
              child: Text('Response',
                  style: _headerStyle)),
        ],
      ),
    );
  }

  static const _headerStyle = TextStyle(
      color: Colors.white38,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5);
}

// ─── Single history row ───────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final int index;

  const _HistoryRow({required this.doc, required this.index});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final profile = data['userProfile'] as Map<String, dynamic>? ?? {};

    final name = profile['name'] ??
        profile['displayName'] ??
        data['userName'] ??
        'Unknown';
    final phone =
        profile['phone'] ?? profile['phoneNumber'] ?? data['phone'] ?? '—';
    final address = data['address'] ?? data['location'];
    final lat = data['lat'] ?? data['latitude'];
    final lng = data['lng'] ?? data['longitude'];
    final locationText = address as String? ??
        (lat != null && lng != null
            ? '${(lat as num).toStringAsFixed(3)}, ${(lng as num).toStringAsFixed(3)}'
            : '—');

    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : null;
    final endedAt = data['endedAt'] != null
        ? (data['endedAt'] as Timestamp).toDate()
        : null;

    final status = data['status'] as String? ??
        (data['endedAt'] == null ? 'Active' : 'Resolved');

    final responseTime = (createdAt != null && endedAt != null)
        ? endedAt.difference(createdAt)
        : null;

    final statusColor = _statusColor(status);

    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IncidentDetailsScreen(sessionDoc: doc),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Index
              SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ),
              // User
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (phone != '—')
                      Text(phone,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              // Location
              Expanded(
                flex: 2,
                child: Text(
                  locationText,
                  style: const TextStyle(color: Colors.blueAccent, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Date & Time
              Expanded(
                flex: 2,
                child: createdAt != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(createdAt),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            _formatTime(createdAt),
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      )
                    : const Text('—',
                        style: TextStyle(color: Colors.white38)),
              ),
              // Status
              Expanded(
                flex: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Response time
              Expanded(
                flex: 2,
                child: responseTime != null
                    ? _ResponseTimeChip(duration: responseTime)
                    : const Text(
                        'In progress',
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s) => switch (s.toLowerCase()) {
        'active' => Colors.redAccent,
        'pending' => Colors.orangeAccent,
        'verified' => Colors.blueAccent,
        'ambulance sent' => Colors.purpleAccent,
        'police notified' => Colors.cyanAccent,
        'resolved' => Colors.greenAccent,
        _ => Colors.grey,
      };

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ─── Response time chip ───────────────────────────────────────────────────────

class _ResponseTimeChip extends StatelessWidget {
  final Duration duration;
  const _ResponseTimeChip({required this.duration});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _format(duration);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  (String, Color) _format(Duration d) {
    if (d.inSeconds < 60) {
      return ('${d.inSeconds}s', Colors.greenAccent);
    } else if (d.inMinutes < 60) {
      final color = d.inMinutes < 15
          ? Colors.greenAccent
          : d.inMinutes < 30
              ? Colors.orangeAccent
              : Colors.redAccent;
      return ('${d.inMinutes}m ${d.inSeconds % 60}s', color);
    } else {
      return ('${d.inHours}h ${d.inMinutes % 60}m', Colors.redAccent);
    }
  }
}

// ─── Date range enum ──────────────────────────────────────────────────────────

enum _DateRange {
  today('Today'),
  week('Week'),
  month('Month'),
  all('All Time');

  final String label;
  const _DateRange(this.label);

  DateTime? get cutoff {
    final now = DateTime.now();
    return switch (this) {
      _DateRange.today =>
        DateTime(now.year, now.month, now.day),
      _DateRange.week =>
        now.subtract(const Duration(days: 7)),
      _DateRange.month =>
        now.subtract(const Duration(days: 30)),
      _DateRange.all => null,
    };
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// NightSafetyService
///
/// Provides night-time context detection:
/// - isNightTime: true between 20:00 and 05:59
/// - riskLevel: based on hour (late night = higher)
/// - Integrates with existing SOS / SafeWalk features
class NightSafetyService {
  static bool get isNightTime {
    final h = DateTime.now().hour;
    return h >= 20 || h < 6;
  }

  static NightRiskLevel get riskLevel {
    final h = DateTime.now().hour;
    if (h >= 0 && h < 4) return NightRiskLevel.high;
    if ((h >= 22 && h <= 23) || (h >= 4 && h < 6)) {
      return NightRiskLevel.medium;
    }
    if (h >= 20 && h < 22) return NightRiskLevel.low;
    return NightRiskLevel.none;
  }

  static String get riskLabel {
    switch (riskLevel) {
      case NightRiskLevel.high:
        return 'HIGH RISK — Late Night (12 AM–4 AM)';
      case NightRiskLevel.medium:
        return 'MEDIUM RISK — Night Hours';
      case NightRiskLevel.low:
        return 'LOW RISK — Early Evening';
      case NightRiskLevel.none:
        return 'DAYTIME — Normal';
    }
  }

  static Color get riskColor {
    switch (riskLevel) {
      case NightRiskLevel.high:
        return const Color(0xFFFF3B3B);
      case NightRiskLevel.medium:
        return const Color(0xFFFF9F0A);
      case NightRiskLevel.low:
        return const Color(0xFF7B5CFA);
      case NightRiskLevel.none:
        return const Color(0xFF4ADE80);
    }
  }

  static String get safetyTip {
    final h = DateTime.now().hour;
    if (h >= 0 && h < 4) {
      return 'Stay indoors if possible. If out, share live location with a trusted contact and keep SOS ready.';
    }
    if (h >= 20 && h < 24) {
      return 'Avoid isolated areas. Use well-lit routes and stay connected with a trusted contact.';
    }
    if (h >= 4 && h < 6) {
      return 'Early morning hours can be unsafe. Stick to known routes and stay alert.';
    }
    return 'Stay aware of your surroundings.';
  }
}

enum NightRiskLevel { none, low, medium, high }

/// NightSafetyScreen
///
/// Displays real-time night safety status with:
/// - Current risk level & time-based advisory
/// - Auto-start SafeWalk prompt at night
/// - Check-in timer (triggers SOS if no response)
/// - Quick SOS button
class NightSafetyScreen extends StatefulWidget {
  final VoidCallback onSosTap;
  final VoidCallback? onSafeWalkTap;

  const NightSafetyScreen({
    super.key,
    required this.onSosTap,
    this.onSafeWalkTap,
  });

  @override
  State<NightSafetyScreen> createState() => _NightSafetyScreenState();
}

class _NightSafetyScreenState extends State<NightSafetyScreen>
    with SingleTickerProviderStateMixin {
  Timer? _clockTimer;
  Timer? _checkInTimer;
  late AnimationController _pulseCtrl;

  int _checkInMinutes = 15;
  int _checkInSecondsLeft = 0;
  bool _checkInActive = false;
  DateTime _now = DateTime.now();

  static const _bg = Color(0xFF0A0A0F);
  static const _card = Color(0xFF13131A);
  static const _border = Color(0xFF2A2A3A);

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  void _startCheckIn() {
    setState(() {
      _checkInActive = true;
      _checkInSecondsLeft = _checkInMinutes * 60;
    });
    HapticFeedback.mediumImpact();

    _checkInTimer?.cancel();
    _checkInTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_checkInSecondsLeft > 0) {
          _checkInSecondsLeft--;
        } else {
          // Timer expired — trigger SOS automatically
          _checkInTimer?.cancel();
          _checkInActive = false;
          widget.onSosTap();
          _showAutoSosDialog();
        }
      });
    });
  }

  void _cancelCheckIn() {
    _checkInTimer?.cancel();
    HapticFeedback.lightImpact();
    setState(() {
      _checkInActive = false;
      _checkInSecondsLeft = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('✅ Check-in cancelled — you\'re marked safe'),
          backgroundColor: Color(0xFF4ADE80)),
    );
  }

  void _showAutoSosDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_rounded, color: Color(0xFFFF3B3B), size: 28),
          SizedBox(width: 10),
          Text('Auto-SOS Triggered',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ]),
        content: const Text(
          'No check-in received. SOS has been automatically sent to your emergency contacts and police.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style: TextStyle(color: Color(0xFF7B5CFA))),
          )
        ],
      ),
    );
  }

  String _formatCountdown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isNight = NightSafetyService.isNightTime;
    final risk = NightSafetyService.riskLevel;
    final riskColor = NightSafetyService.riskColor;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('🌙 Night Safety Intelligence',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Risk status card
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(
                      isNight ? 0.06 + (_pulseCtrl.value * 0.04) : 0.06),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: riskColor.withOpacity(0.5), width: 1.5),
                ),
                child: Column(
                  children: [
                    Text(
                      isNight ? '🌙' : '☀️',
                      style: const TextStyle(fontSize: 48),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _now.hour == 0
                          ? 'Midnight'
                          : '${_now.hour > 12 ? _now.hour - 12 : _now.hour == 0 ? 12 : _now.hour}:${_now.minute.toString().padLeft(2, '0')} ${_now.hour >= 12 ? 'PM' : 'AM'}',
                      style: TextStyle(
                          color: riskColor,
                          fontSize: 28,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: riskColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        NightSafetyService.riskLabel,
                        style: TextStyle(
                            color: riskColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      NightSafetyService.safetyTip,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Check-in timer
            _sectionLabel('⏱ Safety Check-In Timer'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'If you don\'t check in before the timer ends, SOS is auto-triggered.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (!_checkInActive) ...[
                    Row(
                      children: [
                        const Text('Timer:',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 14)),
                        const SizedBox(width: 12),
                        ...([5, 10, 15, 30]).map((m) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _checkInMinutes = m),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _checkInMinutes == m
                                    ? const Color(0xFF7B5CFA)
                                    : _border,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${m}m',
                                  style: TextStyle(
                                      color: _checkInMinutes == m
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ),
                          ),
                        )),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.timer_outlined,
                            size: 18, color: Colors.white),
                        label: Text(
                            'Start $_checkInMinutes-min Check-in',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        onPressed: _startCheckIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B5CFA),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ] else ...[
                    Center(
                      child: Column(
                        children: [
                          Text(
                            _formatCountdown(_checkInSecondsLeft),
                            style: TextStyle(
                                color: _checkInSecondsLeft < 60
                                    ? const Color(0xFFFF3B3B)
                                    : const Color(0xFF7B5CFA),
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 4),
                          const Text('until auto-SOS',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.check_circle_outline,
                                  color: Colors.white, size: 18),
                              label: const Text("I'm Safe — Cancel Timer",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              onPressed: _cancelCheckIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF4ADE80).withOpacity(0.8),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Night safety tips
            _sectionLabel('💡 Night Safety Tips'),
            const SizedBox(height: 10),
            ..._tips.map((tip) => _tipCard(tip['icon']!, tip['text']!)),

            const SizedBox(height: 20),

            // Action buttons
            if (isNight) ...[
              Row(children: [
                Expanded(
                  child: _actionButton(
                    icon: Icons.directions_walk_rounded,
                    label: 'Safe Walk',
                    color: const Color(0xFF7B5CFA),
                    onTap: widget.onSafeWalkTap ?? () {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionButton(
                    icon: Icons.sos_rounded,
                    label: 'SOS',
                    color: const Color(0xFFFF3B3B),
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      widget.onSosTap();
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 30),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _tipCard(String icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: Color(0xFF7B5CFA),
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 0.5),
      );

  static const _tips = [
    {
      'icon': '📍',
      'text': 'Share your live location with a trusted contact before going out at night.'
    },
    {
      'icon': '💡',
      'text': 'Stick to well-lit, populated routes. Avoid shortcuts through dark or isolated areas.'
    },
    {
      'icon': '📵',
      'text': 'Avoid using your phone while walking. Stay alert and aware of your surroundings.'
    },
    {
      'icon': '🚗',
      'text': 'Prefer verified cab services. Share ride details with a contact before boarding.'
    },
    {
      'icon': '🤝',
      'text': 'Travel with a companion when possible, especially between midnight and 4 AM.'
    },
  ];

  @override
  void dispose() {
    _clockTimer?.cancel();
    _checkInTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }
}

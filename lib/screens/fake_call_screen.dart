import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class FakeCallScreen extends StatefulWidget {
  const FakeCallScreen({super.key});

  @override
  State<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<FakeCallScreen>
    with SingleTickerProviderStateMixin {
  bool _callActive = false;
  bool _ringing = false;
  Timer? _ringTimer;
  Timer? _callTimer;
  int _callSeconds = 0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // Fake caller details
  String _callerName = 'Mom';
  final List<String> _presetCallers = ['Mom', 'Dad', 'Office', 'Doctor', 'Boss'];
  int _ringDelaySeconds = 5;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    _callTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startFakeCall() {
    setState(() => _ringing = false);
    // Delay then show incoming call
    _ringTimer = Timer(Duration(seconds: _ringDelaySeconds), () {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() => _ringing = true);
        // Show full-screen incoming call UI
        _showIncomingCallOverlay();
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('📱 Fake call from $_callerName in $_ringDelaySeconds seconds...'),
          backgroundColor: const Color(0xFF1A1A2E),
          duration: Duration(seconds: _ringDelaySeconds),
        ),
      );
    }
  }

  void _showIncomingCallOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      builder: (ctx) => _IncomingCallDialog(
        callerName: _callerName,
        pulseAnim: _pulseAnim,
        onAnswer: () {
          Navigator.pop(ctx);
          _startActiveCall();
        },
        onDecline: () {
          Navigator.pop(ctx);
          setState(() => _ringing = false);
        },
      ),
    );
  }

  void _startActiveCall() {
    setState(() {
      _callActive = true;
      _ringing = false;
      _callSeconds = 0;
    });
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  void _endCall() {
    _callTimer?.cancel();
    setState(() {
      _callActive = false;
      _callSeconds = 0;
    });
  }

  String _formatCallTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('📞 Fake Call',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B9D).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFFFF6B9D).withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Color(0xFFFF6B9D), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Simulate an incoming call to escape uncomfortable or dangerous situations.',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Caller name picker
            const Text('Caller Name',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _presetCallers.map((name) {
                final selected = _callerName == name;
                return GestureDetector(
                  onTap: () => setState(() => _callerName = name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFFF6B9D).withOpacity(0.15)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFFF6B9D)
                            : Colors.white24,
                      ),
                    ),
                    child: Text(name,
                        style: TextStyle(
                            color: selected
                                ? const Color(0xFFFF6B9D)
                                : Colors.white60,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 28),

            // Delay picker
            const Text('Call arrives in...',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [5, 10, 15, 30].map((sec) {
                final selected = _ringDelaySeconds == sec;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _ringDelaySeconds = sec),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFFF6B9D).withOpacity(0.15)
                            : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFFF6B9D)
                              : Colors.white24,
                        ),
                      ),
                      child: Text(
                        '${sec}s',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: selected
                                ? const Color(0xFFFF6B9D)
                                : Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 36),

            // Trigger button
            if (!_callActive)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startFakeCall,
                  icon: const Icon(Icons.phone_rounded, color: Colors.white),
                  label: Text(
                    'Trigger Fake Call from $_callerName',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B9D),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              )
            else
              // Active call UI
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D2B0D),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF00C851).withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.phone_in_talk_rounded,
                        color: Color(0xFF00C851), size: 40),
                    const SizedBox(height: 12),
                    Text(_callerName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_formatCallTime(_callSeconds),
                        style: const TextStyle(
                            color: Color(0xFF00C851), fontSize: 18)),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _endCall,
                        icon: const Icon(Icons.call_end_rounded,
                            color: Colors.white),
                        label: const Text('End Call',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Incoming Call Full-Screen Dialog ─────────────────────────────────────────
class _IncomingCallDialog extends StatelessWidget {
  final String callerName;
  final Animation<double> pulseAnim;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const _IncomingCallDialog({
    required this.callerName,
    required this.pulseAnim,
    required this.onAnswer,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A0D),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            const Text('Incoming Call',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 20),

            // Avatar with pulse
            ScaleTransition(
              scale: pulseAnim,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00C851).withOpacity(0.15),
                  border: Border.all(color: const Color(0xFF00C851), width: 2),
                ),
                child: const Icon(Icons.person_rounded,
                    color: Color(0xFF00C851), size: 60),
              ),
            ),

            const SizedBox(height: 24),
            Text(callerName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Mobile',
                style: TextStyle(color: Colors.white38, fontSize: 16)),

            const Spacer(),

            // Answer / Decline
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Decline
                  _CallButton(
                    icon: Icons.call_end_rounded,
                    color: Colors.redAccent,
                    label: 'Decline',
                    onTap: onDecline,
                  ),
                  // Answer
                  _CallButton(
                    icon: Icons.call_rounded,
                    color: const Color(0xFF00C851),
                    label: 'Answer',
                    onTap: onAnswer,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 10),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 14)),
      ],
    );
  }
}

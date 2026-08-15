import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/live_tracking_service.dart';
import '../services/contacts_db.dart';
import '../providers.dart';

class SafeWalkScreen extends ConsumerStatefulWidget {
  const SafeWalkScreen({super.key});

  @override
  ConsumerState<SafeWalkScreen> createState() => _SafeWalkScreenState();
}

class _SafeWalkScreenState extends ConsumerState<SafeWalkScreen> {
  static const _smsChannel = MethodChannel('com.crashaid/sms');

  Timer? _ticker;
  int _secondsElapsed = 0;
  String _trackingUrl = '';

  bool get _isActive => ref.watch(safeWalkActiveProvider);

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _startSafeWalk() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      await LiveTrackingService.startTracking('Safe Walk', seedPosition: pos);
      final url = LiveTrackingService.getTrackingUrlFromPosition(pos);

      setState(() => _trackingUrl = url);
      ref.read(safeWalkActiveProvider.notifier).state = true;

      // Notify contacts
      final numbers = await ContactsDb.instance.readNumbers(null);
      if (numbers.isNotEmpty) {
        final message =
            '👩 Safe Walk Started\nI am walking and sharing my live location with you.\nTrack me here: $url\nI will send "I Arrived Safe" when I reach my destination.';
        await _smsChannel.invokeMethod('sendSMS', {
          'numbers': numbers,
          'message': message,
        });
      }

      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _secondsElapsed++);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('👩 Safe Walk started — contacts notified'),
            backgroundColor: Color(0xFF00C851),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _markArrived() async {
    _ticker?.cancel();
    await LiveTrackingService.stopTracking();
    ref.read(safeWalkActiveProvider.notifier).state = false;

    final numbers = await ContactsDb.instance.readNumbers(null);
    if (numbers.isNotEmpty) {
      const message =
          '✅ I Arrived Safe!\nThis is an automated message from CrashAid — I have reached my destination safely. Safe Walk session has ended.';
      await _smsChannel.invokeMethod('sendSMS', {
        'numbers': numbers,
        'message': message,
      });
    }

    setState(() {
      _secondsElapsed = 0;
      _trackingUrl = '';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Arrived Safe — contacts notified!'),
          backgroundColor: Color(0xFF00C851),
        ),
      );
    }
  }

  String _formatTime(int seconds) {
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
        title: const Text('👩 Safe Walk Mode',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Status circle
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isActive
                    ? const Color(0xFF00C851).withOpacity(0.12)
                    : Colors.white.withOpacity(0.05),
                border: Border.all(
                  color: _isActive
                      ? const Color(0xFF00C851)
                      : Colors.white24,
                  width: 2.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isActive
                        ? Icons.directions_walk_rounded
                        : Icons.shield_rounded,
                    color: _isActive
                        ? const Color(0xFF00C851)
                        : Colors.white38,
                    size: 52,
                  ),
                  if (_isActive) ...[
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(_secondsElapsed),
                      style: const TextStyle(
                          color: Color(0xFF00C851),
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 28),

            Text(
              _isActive ? 'Safe Walk Active' : 'Safe Walk',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isActive
                  ? 'Your live location is being shared\nwith your emergency contacts.'
                  : 'Share your live location with trusted\ncontacts until you arrive safe.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 14, height: 1.5),
            ),

            if (_isActive && _trackingUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C851).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF00C851).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        color: Color(0xFF00C851), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _trackingUrl,
                        style: const TextStyle(
                            color: Color(0xFF00C851), fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 36),

            if (!_isActive)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startSafeWalk,
                  icon: const Icon(Icons.directions_walk_rounded,
                      color: Colors.white),
                  label: const Text('Start Safe Walk',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C851),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              )
            else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _markArrived,
                  icon: const Icon(Icons.check_circle_rounded,
                      color: Colors.white),
                  label: const Text('I Arrived Safe ✅',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C851),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Pop back to home and trigger SOS
                    Navigator.pop(context, 'sos');
                  },
                  icon: const Icon(Icons.warning_rounded,
                      color: Color(0xFFFF3B3B)),
                  label: const Text('🚨 Send SOS Now',
                      style: TextStyle(
                          color: Color(0xFFFF3B3B),
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFF3B3B)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How it works',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  SizedBox(height: 10),
                  _InfoRow(icon: Icons.sms_outlined,
                      text: 'Contacts get your live tracking link via SMS'),
                  _InfoRow(icon: Icons.location_on_rounded,
                      text: 'Your GPS location updates every 10 metres'),
                  _InfoRow(icon: Icons.check_circle_outline,
                      text: 'Tap "I Arrived Safe" to end and notify contacts'),
                  _InfoRow(icon: Icons.warning_amber_rounded,
                      text: 'SOS button fires emergency alert instantly'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00C851), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

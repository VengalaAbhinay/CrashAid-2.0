import 'dart:async';
import 'package:flutter/material.dart';
import '../services/safe_route_service.dart';

class SafeRouteChildScreen extends StatefulWidget {
  final VoidCallback? onSosTap;
  const SafeRouteChildScreen({super.key, this.onSosTap});

  @override
  State<SafeRouteChildScreen> createState() => _SafeRouteChildScreenState();
}

class _SafeRouteChildScreenState extends State<SafeRouteChildScreen> {
  final _codeController = TextEditingController();
  Timer? _ticker;
  int _secondsElapsed = 0;
  bool _isJoining = false;
  bool _isSharing = false;
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinAndShare() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _error = 'Enter the code your parent shared with you');
      return;
    }

    setState(() {
      _isJoining = true;
      _error = null;
    });

    final exists = await SafeRouteSession.codeExists(code);
    if (!exists) {
      setState(() {
        _isJoining = false;
        _error = 'That code wasn\'t found or has expired. Ask for a new one.';
      });
      return;
    }

    final joined = await SafeRouteSession.joinAsChild(code);
    if (!joined) {
      setState(() {
        _isJoining = false;
        _error = 'Couldn\'t start sharing — check location permission and try again.';
      });
      return;
    }

    setState(() {
      _isJoining = false;
      _isSharing = true;
      _secondsElapsed = 0;
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📡 Sharing started — your parent can now see you'),
          backgroundColor: Color(0xFF00C851),
        ),
      );
    }
  }

  Future<void> _stopSharing() async {
    _ticker?.cancel();
    await SafeRouteSession.stopChildSharing();
    setState(() {
      _isSharing = false;
      _secondsElapsed = 0;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stopped sharing your location'),
          backgroundColor: Colors.white24,
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
        title: const Text('🧒 Child — Share Location',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isSharing
                    ? const Color(0xFF00C851).withOpacity(0.12)
                    : Colors.white.withOpacity(0.05),
                border: Border.all(
                  color: _isSharing ? const Color(0xFF00C851) : Colors.white24,
                  width: 2.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isSharing ? Icons.sensors_rounded : Icons.child_care_rounded,
                    color: _isSharing ? const Color(0xFF00C851) : Colors.white38,
                    size: 52,
                  ),
                  if (_isSharing) ...[
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
              _isSharing ? 'Sharing Your Location' : 'Join Safe Route',
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isSharing
                  ? 'Your parent is watching your live location\nagainst the route they drew.'
                  : 'Enter the code your parent shared with you.\nYour phone only sends your GPS — nothing else.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),

            if (!_isSharing) ...[
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'CODE',
                  hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 6),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isJoining ? null : _joinAndShare,
                  icon: _isJoining
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.sensors_rounded, color: Colors.white),
                  label: Text(_isJoining ? 'Joining…' : 'Start Sharing',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C851),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _stopSharing,
                  icon: const Icon(Icons.stop_circle_rounded, color: Colors.white),
                  label: const Text('Stop Sharing',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              if (widget.onSosTap != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onSosTap,
                    icon: const Icon(Icons.warning_rounded, color: Color(0xFFFF3B3B)),
                    label: const Text('🚨 Send SOS Now',
                        style: TextStyle(
                            color: Color(0xFFFF3B3B), fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFF3B3B)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 28),
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
                  _InfoRow(
                      icon: Icons.key_rounded,
                      text: 'Enter the code shown on your parent\'s phone'),
                  _InfoRow(
                      icon: Icons.location_on_rounded,
                      text: 'Your GPS is sent so they can see you on the route'),
                  _InfoRow(
                      icon: Icons.block_rounded,
                      text: 'This phone never draws the route or sends alerts itself'),
                  _InfoRow(
                      icon: Icons.warning_amber_rounded,
                      text: 'SOS button fires an emergency alert instantly'),
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

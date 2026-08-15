import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers.dart';
import 'safe_walk_screen.dart';
import 'fake_call_screen.dart';

class WomenSafetyScreen extends ConsumerWidget {
  final VoidCallback onSosTap;
  const WomenSafetyScreen({super.key, required this.onSosTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('👩 Women Safety',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Panic SOS button
            GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                onSosTap();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B3B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: const Color(0xFFFF3B3B).withOpacity(0.6),
                      width: 2),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.warning_rounded,
                        color: Color(0xFFFF3B3B), size: 48),
                    SizedBox(height: 12),
                    Text('🚨 PANIC SOS',
                        style: TextStyle(
                            color: Color(0xFFFF3B3B),
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Tap to instantly alert all emergency contacts',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Volume button tip
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B9D).withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFFF6B9D).withOpacity(0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.volume_down_rounded,
                      color: Color(0xFFFF6B9D), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Silent Panic: Hold Volume Down for 2 seconds to send SOS without unlocking your phone.',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Feature grid
            Row(
              children: [
                Expanded(
                  child: _FeatureCard(
                    icon: Icons.directions_walk_rounded,
                    title: 'Safe Walk',
                    subtitle: 'Share live location until you arrive',
                    color: const Color(0xFF00C851),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SafeWalkScreen())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FeatureCard(
                    icon: Icons.phone_rounded,
                    title: 'Fake Call',
                    subtitle: 'Simulate incoming call to escape',
                    color: const Color(0xFFFF6B9D),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const FakeCallScreen())),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Safety tips
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
                  Text('Quick Tips',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  SizedBox(height: 12),
                  _TipRow(
                      emoji: '📍',
                      text:
                          'Keep GPS enabled for accurate location sharing'),
                  _TipRow(
                      emoji: '🔇',
                      text:
                          'Volume button SOS works even when phone is locked'),
                  _TipRow(
                      emoji: '📱',
                      text:
                          'Use Fake Call in taxis or uncomfortable situations'),
                  _TipRow(
                      emoji: '🚶',
                      text:
                          'Start Safe Walk before leaving — not after trouble begins'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Emergency numbers
            Row(
              children: [
                _EmergencyBtn(label: '🚔 Police', number: '100',
                    color: const Color(0xFF3B6FFF)),
                const SizedBox(width: 10),
                _EmergencyBtn(label: '🆘 Women', number: '1091',
                    color: const Color(0xFFFF6B9D)),
                const SizedBox(width: 10),
                _EmergencyBtn(label: '🚑 Ambulance', number: '108',
                    color: const Color(0xFFFF3B3B)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final String emoji;
  final String text;
  const _TipRow({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12))),
        ],
      ),
    );
  }
}

class _EmergencyBtn extends StatelessWidget {
  final String label;
  final String number;
  final Color color;
  const _EmergencyBtn(
      {required this.label, required this.number, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          final uri = Uri(scheme: 'tel', path: number);
          // ignore: deprecated_member_use
          await launchUrl(uri);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Text(label.split(' ')[0],
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(label.split(' ')[1],
                  style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.w600)),
              Text(number,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
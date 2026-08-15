import 'package:flutter/material.dart';
import 'safe_route_parent_screen.dart';
import 'safe_route_child_screen.dart';

/// Entry point for "Child Safety / Safe Route". Routes to one of two
/// genuinely separate roles, each running on its own device:
///   • Parent: draws the route and monitors live progress
///   • Child:  enters the parent's code and shares live GPS only
class SafeRouteScreen extends StatelessWidget {
  final VoidCallback? onSosTap;
  const SafeRouteScreen({super.key, this.onSosTap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('👦 Child Safety',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            const Icon(Icons.shield_moon_rounded,
                color: Color(0xFF3B6FFF), size: 64),
            const SizedBox(height: 16),
            const Text('Safe Route Monitoring',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'This works across two phones — one draws the route and watches, the other shares its live location.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 32),
            _RoleCard(
              emoji: '👨‍👩‍👧',
              title: "I'm the Parent",
              subtitle: 'Draw the route, get a code, and monitor live location',
              color: const Color(0xFF3B6FFF),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SafeRouteParentScreen(onSosTap: onSosTap)),
              ),
            ),
            const SizedBox(height: 16),
            _RoleCard(
              emoji: '🧒',
              title: "I'm the Child",
              subtitle: 'Enter the code and share your live location',
              color: const Color(0xFF00C851),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SafeRouteChildScreen(onSosTap: onSosTap)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String emoji, title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _RoleCard({
    required this.emoji,
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
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import 'safe_walk_screen.dart';
import 'fake_call_screen.dart';
import 'safe_route_screen.dart';

class ProfileModeScreen extends ConsumerWidget {
  const ProfileModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(userModeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Safety Mode',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Your Profile',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
                'Choose your mode to activate relevant safety features.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 24),

            // Mode cards
            _ModeCard(
              mode: UserMode.driver,
              currentMode: currentMode,
              emoji: '🚗',
              title: 'Driver Mode',
              subtitle: 'Auto crash detection + SOS',
              color: const Color(0xFFFF3B3B),
              features: [
                'Automatic crash detection',
                'Speed gate (no false alarms)',
                '10-second cancel window',
                'Live GPS tracking after crash',
              ],
              onSelect: () =>
                  ref.read(userModeProvider.notifier).setMode(UserMode.driver),
            ),

            const SizedBox(height: 14),

            _ModeCard(
              mode: UserMode.women,
              currentMode: currentMode,
              emoji: '👩',
              title: 'Women Safety Mode',
              subtitle: 'Panic button + Safe Walk + Fake Call',
              color: const Color(0xFFFF6B9D),
              features: [
                'Silent panic button (volume press)',
                'Safe Walk with live location sharing',
                'Fake incoming call to escape danger',
                'Voice SOS trigger',
              ],
              onSelect: () =>
                  ref.read(userModeProvider.notifier).setMode(UserMode.women),
              onFeatureTap: (feature) {
                if (feature.contains('Safe Walk')) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SafeWalkScreen()));
                } else if (feature.contains('Fake')) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const FakeCallScreen()));
                }
              },
            ),

            const SizedBox(height: 14),

            _ModeCard(
              mode: UserMode.senior,
              currentMode: currentMode,
              emoji: '👴',
              title: 'Senior Citizen Mode',
              subtitle: 'Fall detection + Shake SOS',
              color: const Color(0xFFFF8C3B),
              features: [
                'Fall detection (accelerometer)',
                'Shake phone 3x to send SOS',
                '10-second cancel window',
                'Auto AI first aid after fall',
              ],
              onSelect: () =>
                  ref.read(userModeProvider.notifier).setMode(UserMode.senior),
            ),

            const SizedBox(height: 14),

            _ModeCard(
              mode: UserMode.child,
              currentMode: currentMode,
              emoji: '👦',
              title: 'Child Safety Mode',
              subtitle: 'Safe route + Stranger danger button',
              color: const Color(0xFF3B6FFF),
              features: [
                'Safe route monitoring (home → school)',
                '300m deviation alert to parents',
                'School arrival notification',
                'One-tap Stranger Danger SOS',
              ],
              onSelect: () =>
                  ref.read(userModeProvider.notifier).setMode(UserMode.child),
              onFeatureTap: (feature) {
                if (feature.contains('route')) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SafeRouteScreen()));
                }
              },
            ),

            const SizedBox(height: 28),

            // Active mode features
            if (currentMode != UserMode.driver) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _modeColor(currentMode).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: _modeColor(currentMode).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: _modeColor(currentMode), size: 18),
                        const SizedBox(width: 8),
                        Text('${_modeName(currentMode)} Active',
                            style: TextStyle(
                                color: _modeColor(currentMode),
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_modeActiveDesc(currentMode),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _modeColor(UserMode mode) {
    return switch (mode) {
      UserMode.driver => const Color(0xFFFF3B3B),
      UserMode.women => const Color(0xFFFF6B9D),
      UserMode.senior => const Color(0xFFFF8C3B),
      UserMode.child => const Color(0xFF3B6FFF),
    };
  }

  String _modeName(UserMode mode) {
    return switch (mode) {
      UserMode.driver => '🚗 Driver Mode',
      UserMode.women => '👩 Women Safety',
      UserMode.senior => '👴 Senior Mode',
      UserMode.child => '👦 Child Safety',
    };
  }

  String _modeActiveDesc(UserMode mode) {
    return switch (mode) {
      UserMode.driver =>
        'Crash detection is active. Drive safely.',
      UserMode.women =>
        'Panic button and Safe Walk are active. Volume press triggers silent SOS.',
      UserMode.senior =>
        'Fall detection and Shake-to-SOS are active. Shake phone 3 times or fall triggers SOS.',
      UserMode.child =>
        'Safe route monitoring is available. Set a route from home to school to monitor your child.',
    };
  }
}

// ── Mode Card ────────────────────────────────────────────────────────────────
class _ModeCard extends StatelessWidget {
  final UserMode mode;
  final UserMode currentMode;
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final List<String> features;
  final VoidCallback onSelect;
  final void Function(String feature)? onFeatureTap;

  const _ModeCard({
    required this.mode,
    required this.currentMode,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.features,
    required this.onSelect,
    this.onFeatureTap,
  });

  bool get _isSelected => currentMode == mode;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _isSelected
              ? color.withOpacity(0.1)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isSelected ? color.withOpacity(0.7) : Colors.white12,
            width: _isSelected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: _isSelected ? color : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                if (_isSelected)
                  Icon(Icons.check_circle_rounded, color: color, size: 22)
                else
                  Icon(Icons.radio_button_unchecked_rounded,
                      color: Colors.white24, size: 22),
              ],
            ),
            if (_isSelected) ...[
              const SizedBox(height: 14),
              const Divider(color: Colors.white10),
              const SizedBox(height: 10),
              ...features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: GestureDetector(
                      onTap: onFeatureTap != null
                          ? () => onFeatureTap!(f)
                          : null,
                      child: Row(
                        children: [
                          Icon(Icons.check_rounded, color: color, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(f,
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    decoration: onFeatureTap != null
                                        ? TextDecoration.underline
                                        : null)),
                          ),
                          if (onFeatureTap != null &&
                              (f.contains('Safe Walk') ||
                                  f.contains('Fake') ||
                                  f.contains('route')))
                            Icon(Icons.open_in_new_rounded,
                                color: color, size: 14),
                        ],
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../screens/night_safety_screen.dart';

/// Auto-appears on the home screen whenever NightSafetyService.isNightTime
/// is true (8 PM – 6 AM). Tapping it opens the full Night Safety screen
/// with the check-in timer.
class NightSafetyBanner extends StatelessWidget {
  final VoidCallback onSosTap;
  final VoidCallback? onSafeWalkTap;

  const NightSafetyBanner({
    super.key,
    required this.onSosTap,
    this.onSafeWalkTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!NightSafetyService.isNightTime) return const SizedBox.shrink();

    final color = NightSafetyService.riskColor;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NightSafetyScreen(
            onSosTap: onSosTap,
            onSafeWalkTap: onSafeWalkTap,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.nights_stay_rounded, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(NightSafetyService.riskLabel,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(NightSafetyService.safetyTip,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

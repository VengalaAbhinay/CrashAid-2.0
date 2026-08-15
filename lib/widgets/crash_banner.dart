import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/live_tracking_service.dart';
import '../screens/live_tracking_map_screen.dart';

class LiveTrackingBanner extends StatelessWidget {
  final VoidCallback onImSafe;
  const LiveTrackingBanner({super.key, required this.onImSafe});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B3B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF3B3B).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Color(0xFFFF3B3B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.liveTrackingActive,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFFF3B3B),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
                Text(loc.contactsCanSeeLocation,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              final url = LiveTrackingService.getLiveTrackingUrl();
              final sessionId = url.contains('id=') ? url.split('id=').last : null;
              if (sessionId != null && sessionId.isNotEmpty) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => LiveTrackingMapScreen(sessionId: sessionId)));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF3B6FFF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3B6FFF).withValues(alpha: 0.4)),
              ),
              child: const Text('🗺 Map',
                  maxLines: 1,
                  style: TextStyle(color: Color(0xFF3B6FFF), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onImSafe,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00C851).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00C851).withValues(alpha: 0.4)),
              ),
              child: Text(loc.imSafe,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF00C851), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class CrashDetectedBanner extends StatelessWidget {
  final VoidCallback onSosAgain;
  final VoidCallback onImSafe;

  const CrashDetectedBanner({
    super.key,
    required this.onSosAgain,
    required this.onImSafe,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B3B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF3B3B).withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3B3B).withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.car_crash_rounded, color: Color(0xFFFF3B3B), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(loc.crashDetected,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFFF3B3B),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B3B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF3B3B).withValues(alpha: 0.4)),
                ),
                child: const Text('🚨 SOS Sent',
                    style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(loc.crashDetectedDesc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onSosAgain,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B3B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFF3B3B).withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_rounded, color: Color(0xFFFF3B3B), size: 14),
                        SizedBox(width: 4),
                        Text('SOS', style: TextStyle(color: Color(0xFFFF3B3B), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: onImSafe,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C851).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00C851).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00C851), size: 14),
                        const SizedBox(width: 4),
                        Text(loc.imSafe,
                            style: const TextStyle(color: Color(0xFF00C851), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

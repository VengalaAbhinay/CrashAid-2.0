import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class SOSSection extends StatelessWidget {
  final Animation<double> pulseAnim;
  final VoidCallback onSosTap;

  const SOSSection({
    super.key,
    required this.pulseAnim,
    required this.onSosTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D0F0F), Color(0xFF1A0505)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFFF3B3B).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3B3B).withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B3B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(loc.oneTapEmergency,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                ),
                const SizedBox(height: 10),
                Text(loc.sendSosLiveTrack,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.2)),
                const SizedBox(height: 6),
                Text(loc.smsToContacts,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        height: 1.4)),
              ],
            ),
          ),
          ScaleTransition(
            scale: pulseAnim,
            child: GestureDetector(
              key: const Key('sos_button'),
              onTap: onSosTap,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFCC0000)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF3B3B).withValues(alpha: 0.5),
                      blurRadius: 25,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_rounded, color: Colors.white, size: 28),
                    SizedBox(height: 4),
                    Text('SOS',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

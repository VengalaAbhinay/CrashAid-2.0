import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class VoiceButton extends StatelessWidget {
  final bool isOn;
  final bool isListening;
  final VoidCallback onTap;

  const VoiceButton({
    super.key,
    required this.isOn,
    required this.isListening,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isOn
                ? const Color(0xFF00C851).withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isOn
                  ? const Color(0xFF00C851).withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  if (isOn)
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00C851).withValues(alpha: 0.15),
                      ),
                    ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOn
                          ? const Color(0xFF00C851).withValues(alpha: 0.20)
                          : Colors.white.withValues(alpha: 0.07),
                    ),
                    child: Icon(
                      isOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      color: isOn ? const Color(0xFF00C851) : Colors.white38,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOn ? loc.voiceDetectionOn : loc.voiceDetectionOff,
                      style: TextStyle(
                        color: isOn ? const Color(0xFF00C851) : Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOn
                          ? (isListening ? loc.voiceListening : loc.voiceStarting)
                          : loc.voiceTapHint,
                      style: TextStyle(
                        color: isOn ? Colors.white54 : Colors.white30,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isOn
                      ? const Color(0xFF00C851)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isOn ? loc.on : loc.off,
                  style: TextStyle(
                    color: isOn ? Colors.white : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

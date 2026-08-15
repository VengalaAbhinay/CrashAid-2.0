import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CRASH CANCEL COUNTDOWN DIALOG
// Extracted from home_screen.dart.
//
// showCrashCancelCountdown — 10-second window shown after crash is detected.
//   Returns true  → user pressed "I'm Safe / Cancel SOS" (SOS should NOT fire).
//   Returns false → countdown elapsed or user pressed "Send SOS Now" (SOS fires).
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the 10-second crash-cancel window.
///
/// Returns `true` if the user cancelled (SOS should NOT fire),
/// or `false` if the countdown elapsed / user pressed "Send SOS Now".
Future<bool> showCrashCancelCountdown(BuildContext context) async {
  int count = 10;
  bool cancelled = false;
  Timer? countdownTimer;
  final notifier = ValueNotifier<int>(count);

  await showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (ctx) {
      countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        count--;
        notifier.value = count;
        if (count <= 0) {
          t.cancel();
          if (Navigator.canPop(ctx)) Navigator.pop(ctx);
        }
      });

      return ValueListenableBuilder<int>(
        valueListenable: notifier,
        builder: (_, seconds, __) => Dialog(
          backgroundColor: Colors.transparent,
          child: Builder(
            builder: (dialogContext) {
              final loc = AppLocalizations.of(dialogContext);
              return Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0A0A),
                  borderRadius: BorderRadius.circular(28),
                  border:
                      Border.all(color: const Color(0xFFFF3B3B), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF3B3B).withValues(alpha: 0.45),
                      blurRadius: 36,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Icon ──────────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFF3B3B).withValues(alpha: 0.15),
                        border: Border.all(
                            color: const Color(0xFFFF3B3B)
                                .withValues(alpha: 0.5)),
                      ),
                      child: const Icon(Icons.car_crash_rounded,
                          color: Color(0xFFFF3B3B), size: 36),
                    ),
                    const SizedBox(height: 16),

                    // ── Title ─────────────────────────────────────────────
                    Text(
                      loc.crashCancelTitle,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),

                    // ── Subtitle ──────────────────────────────────────────
                    Text(
                      loc.crashCancelDesc,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          height: 1.5),
                    ),
                    const SizedBox(height: 20),

                    // ── Countdown ring ────────────────────────────────────
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 90,
                          height: 90,
                          child: CircularProgressIndicator(
                            value: seconds / 10,
                            strokeWidth: 5,
                            backgroundColor: const Color(0xFFFF3B3B)
                                .withValues(alpha: 0.15),
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(
                                    Color(0xFFFF3B3B)),
                          ),
                        ),
                        Text(
                          '$seconds',
                          style: const TextStyle(
                              fontSize: 36,
                              color: Color(0xFFFF3B3B),
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── "I'm Safe" cancel button ──────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          countdownTimer?.cancel();
                          cancelled = true;
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.cancel_rounded,
                            color: Colors.white, size: 18),
                        label: Text(
                          loc.imSafeCancelSos,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C851),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── "Send SOS Now" button ─────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          countdownTimer?.cancel();
                          Navigator.pop(ctx);
                          // cancelled stays false → SOS fires
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3B3B)
                              .withValues(alpha: 0.12),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                                color: const Color(0xFFFF3B3B)
                                    .withValues(alpha: 0.4)),
                          ),
                        ),
                        child: Text(
                          loc.sendSosNow,
                          style: const TextStyle(
                              color: Color(0xFFFF6B6B),
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  ).then((_) => notifier.dispose());

  return cancelled;
}
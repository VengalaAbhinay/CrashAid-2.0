import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SOS DIALOGS
// Extracted from home_screen.dart.
//
// showSosConfirmDialog  — "Send SOS?" gate (10-s auto-advance).
// showSosCountdownDialog — 10-s countdown before the SOS fires.
// showAfterSosOptionsDialog — post-SOS options (call 112, first aid, I'm safe).
// showSafeDialog        — confirmation that safe-message was sent.
// showNoContactsDialog  — warning shown when contact list is empty.
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the "Send SOS?" confirmation gate.
///
/// [onConfirmed] is called immediately when the user taps "Yes, Send SOS" or
/// the 10-second auto-advance timer elapses — whichever comes first.
void showSosConfirmDialog(
  BuildContext context, {
  required VoidCallback onConfirmed,
}) {
  HapticFeedback.heavyImpact();
  int confirmCountdown = 10;
  Timer? confirmTimer;

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setConfirmState) {
        confirmTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
          if (confirmCountdown == 1) {
            t.cancel();
            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            onConfirmed();
            return;
          }
          confirmCountdown--;
          setConfirmState(() {});
        });

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0A0A),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFFF3B3B), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B3B).withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFFF3B3B), size: 48),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) => Text(
                    AppLocalizations.of(context).sendSosAlert,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) => Text(
                    AppLocalizations.of(context)
                        .sosAutoSendIn
                        .replaceAll('{n}', '$confirmCountdown'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13, height: 1.4),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFFFF3B3B), width: 2.5),
                    color: const Color(0xFFFF3B3B).withValues(alpha: 0.08),
                  ),
                  child: Center(
                    child: Text(
                      '$confirmCountdown',
                      style: const TextStyle(
                          fontSize: 30,
                          color: Color(0xFFFF3B3B),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          confirmTimer?.cancel();
                          Navigator.pop(ctx);
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white12,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Builder(
                          builder: (context) => Text(
                            AppLocalizations.of(context).cancel,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        key: const Key('sos_confirm_button'),
                        onPressed: () {
                          confirmTimer?.cancel();
                          Navigator.pop(ctx);
                          onConfirmed();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3B3B),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Builder(
                          builder: (context) => Text(
                            AppLocalizations.of(context).yesSendSos,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Shows the 10-second SOS countdown dialog.
///
/// [countdownRef] is an int that the caller owns (e.g. `countdown` in
/// `_HomeScreenState`). It is mutated here so the state variable stays in sync.
/// [timerRef] is the caller's nullable `Timer?`; set to null when cancelled.
/// [onSend] is called when the countdown reaches zero (auto-send).
/// [onCancelled] is called when the user taps "Cancel".
void showSosCountdownDialog(
  BuildContext context, {
  required int Function() getCountdown,
  required void Function(int) setCountdown,
  required Timer? Function() getTimer,
  required void Function(Timer?) setTimer,
  required VoidCallback onSend,
  required VoidCallback onCancelled,
}) {
  final loc = AppLocalizations.of(context);
  HapticFeedback.heavyImpact();
  setCountdown(10);

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (sbCtx, setStateDialog) {
          if (getTimer() == null) {
            setTimer(Timer.periodic(const Duration(seconds: 1), (t) {
              if (getCountdown() == 0) {
                t.cancel();
                setTimer(null);
                Navigator.pop(dialogContext);
                onSend();
                return;
              }
              setCountdown(getCountdown() - 1);
              setStateDialog(() {});
            }));
          }

          return Dialog(
            key: const Key('sos_countdown_dialog'),
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0A0A),
                borderRadius: BorderRadius.circular(28),
                border:
                    Border.all(color: const Color(0xFFFF3B3B), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF3B3B).withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFFF3B3B), size: 48),
                  const SizedBox(height: 12),
                  Text(
                    loc.emergencySOS,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loc.sendingLocationIn,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFFF3B3B), width: 3),
                      color:
                          const Color(0xFFFF3B3B).withValues(alpha: 0.1),
                    ),
                    child: Center(
                      child: Text(
                        '${getCountdown()}',
                        style: const TextStyle(
                            fontSize: 44,
                            color: Color(0xFFFF3B3B),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      key: const Key('sos_cancel_button'),
                      onPressed: () {
                        getTimer()?.cancel();
                        setTimer(null);
                        Navigator.pop(dialogContext);
                        onCancelled();
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        loc.cancel,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Shows the voice-triggered 10-second SOS countdown.
///
/// Differs from [showSosCountdownDialog] in that it uses a `ValueNotifier`
/// for efficient rebuilds, shows a circular-progress ring, and re-starts the
/// voice listener on cancel.
void showVoiceSosCountdownDialog(
  BuildContext context, {
  required VoidCallback onSend,
  required VoidCallback onCancelledResumeVoice,
}) {
  if (!Navigator.of(context).canPop() == false) return; // guard

  int sosCount = 10;
  Timer? sosTimer;
  bool sosSent = false;
  final notifier = ValueNotifier<int>(sosCount);

  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (ctx) {
      sosTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        sosCount--;
        notifier.value = sosCount;
        if (sosCount <= 0) {
          t.cancel();
          if (Navigator.canPop(ctx)) Navigator.pop(ctx);
          if (!sosSent) {
            sosSent = true;
            onSend();
          }
        }
      });

      return ValueListenableBuilder<int>(
        valueListenable: notifier,
        builder: (_, count, __) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0A0A),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFFF3B3B), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B3B).withValues(alpha: 0.4),
                  blurRadius: 32,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF3B3B).withValues(alpha: 0.15),
                    border: Border.all(
                        color:
                            const Color(0xFFFF3B3B).withValues(alpha: 0.5)),
                  ),
                  child: const Icon(Icons.warning_rounded,
                      color: Color(0xFFFF3B3B), size: 36),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) => Text(
                    AppLocalizations.of(context).sendingSos,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) => Text(
                    AppLocalizations.of(context).sosBeingSent,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13, height: 1.4),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFFFF3B3B), width: 3),
                    color: const Color(0xFFFF3B3B).withValues(alpha: 0.1),
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: const TextStyle(
                          fontSize: 44,
                          color: Color(0xFFFF3B3B),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      sosTimer?.cancel();
                      sosSent = true; // block auto-send
                      Navigator.pop(ctx);
                      onCancelledResumeVoice();
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white12,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Builder(
                      builder: (context) => Text(
                        AppLocalizations.of(context).cancelImSafe,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) => Text(
                    AppLocalizations.of(context).format(
                        'sendingInSeconds', {'count': '$count'}),
                    style: const TextStyle(
                        color: Colors.white30, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  ).then((_) => notifier.dispose());
}

/// Shows the post-SOS options: call 112, get first aid, or mark safe.
///
/// [onCallEmergency] — tapped "Call 112".
/// [onFirstAid]     — tapped "Get First Aid Guidance".
/// [onImSafe]       — tapped "I'm Safe / Stop Tracking" (async; shows spinner).
void showAfterSosOptionsDialog(
  BuildContext context, {
  required VoidCallback onCallEmergency,
  required VoidCallback onFirstAid,
  required Future<void> Function() onImSafe,
  VoidCallback? onAmbulanceRouting,
}) {
  final loc = AppLocalizations.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    // FIX: collapsed to a single StatefulBuilder so setSt can rebuild the dialog.
    builder: (_) => StatefulBuilder(
      builder: (dialogContext, setSt) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0A0A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: const Color(0xFFFF3B3B).withValues(alpha: 0.4)),
            ),
            child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.alertSentTracking,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc.smsSentToContacts,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                                Navigator.pop(dialogContext);
                                onCallEmergency();
                              },
                        icon:
                            const Icon(Icons.call, color: Colors.white),
                        label: Text(
                          loc.call112Now,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF3B3B),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          onFirstAid();
                        },
                        icon: const Icon(Icons.medical_services_rounded,
                            color: Colors.white),
                        label: const Text(
                          'Get First Aid Guidance',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B6FFF),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    if (onAmbulanceRouting != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            onAmbulanceRouting();
                          },
                          icon: const Icon(Icons.local_hospital_rounded,
                              color: Colors.white),
                          label: const Text(
                            '🚑 Start Ambulance Routing',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00C851),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          // Close dialog immediately — don't await onImSafe()
                          // because it may open WhatsApp/SMS externally and
                          // never return, causing the spinner to hang forever.
                          Navigator.of(dialogContext).pop();
                          onImSafe();
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF00C851)
                              .withValues(alpha: 0.1),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                                color: Color(0xFF00C851)),
                          ),
                        ),
                        child: Text(
                                loc.imSafeStopTracking,
                                style: const TextStyle(
                                    color: Color(0xFF00C851),
                                    fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
            ),
          ),
        );
      },
    ),
  );
}

/// Confirmation dialog shown once the user is marked safe.
void showSafeDialog(BuildContext context) {
  final loc = AppLocalizations.of(context);
  showDialog(
    context: context,
    builder: (dialogCtx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1A0A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: const Color(0xFF00C851).withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('✅', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              loc.youreMarkedSafe,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              loc.liveTrackingStopped,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(dialogCtx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C851),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  loc.ok,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Warning shown when no emergency contacts have been added.
void showNoContactsDialog(BuildContext context) {
  final loc = AppLocalizations.of(context);
  showDialog(
    context: context,
    builder: (dialogCtx2) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: const Color(0xFFFF8C3B).withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              loc.noEmergencyContacts,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              loc.pleaseAddContacts,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(dialogCtx2),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C3B),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  loc.okIllAddContacts,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
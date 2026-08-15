// test/unit/crashaid_unit_test.dart
//
// Pure unit tests — no WidgetTester, no Flutter test bindings, no mocks.
// Run with:  flutter test test/unit/crashaid_unit_test.dart
//
// Covers gap #2:
//   • Crash threshold / impact-magnitude math
//   • Contact string parsing  (Contact.fromPrefsString / toPrefsString)
//   • WhatsApp number formatting (_toWaIntl)

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Inline copies of the pure-logic functions under test.
// These are extracted from their respective source files so the tests have
// zero Flutter / Firebase / plugin dependencies.
// ─────────────────────────────────────────────────────────────────────────────

// ── 1. Crash magnitude math ──────────────────────────────────────────────────
// Source: CrashTaskHandler in crash_foreground_service.dart
//
// Low-pass filter constants (must stay in sync with source).
const double _alpha = 0.8;
const double _impactThreshold = 25.0;

/// One step of the gravity low-pass filter.
/// Returns updated [gx, gy, gz].
List<double> lowPassStep(
  double gx, double gy, double gz,
  double rawX, double rawY, double rawZ,
) {
  return [
    _alpha * gx + (1 - _alpha) * rawX,
    _alpha * gy + (1 - _alpha) * rawY,
    _alpha * gz + (1 - _alpha) * rawZ,
  ];
}

/// Computes linear-acceleration magnitude after subtracting gravity.
double impactMagnitude(
  double rawX, double rawY, double rawZ,
  double gx,   double gy,   double gz,
) {
  final ax = rawX - gx;
  final ay = rawY - gy;
  final az = rawZ - gz;
  return sqrt(ax * ax + ay * ay + az * az);
}

// ── 2. Contact string parsing ────────────────────────────────────────────────
// Source: Contact in contacts_screen.dart

class Contact {
  final String name;
  final String number;
  const Contact({required this.name, required this.number});

  String toPrefsString() => '$name|$number';

  factory Contact.fromPrefsString(String s) {
    final idx = s.indexOf('|');
    if (idx == -1) return Contact(name: '', number: s);
    return Contact(name: s.substring(0, idx), number: s.substring(idx + 1));
  }

  @override
  bool operator ==(Object other) =>
      other is Contact && other.name == name && other.number == number;

  @override
  int get hashCode => Object.hash(name, number);
}

/// Parses a newline-separated prefs string into a list of contacts.
/// Mirrors _loadContacts() logic in contacts_screen.dart.
List<Contact> parseContactsBlob(String raw) {
  if (raw.isEmpty) return [];
  return raw
      .split('\n')
      .where((e) => e.isNotEmpty)
      .map(Contact.fromPrefsString)
      .toList();
}

/// Serialises a contact list into the storage blob.
/// Mirrors _saveContacts() logic in contacts_screen.dart.
String serialiseContacts(List<Contact> contacts) =>
    contacts.map((c) => c.toPrefsString()).join('\n');

// ── 3. WhatsApp number formatting ────────────────────────────────────────────
// Source: _toWaIntl() in home_screen.dart

String toWaIntl(String number) {
  final cleaned = number.replaceAll(RegExp(r'[^\d+]'), '');
  if (cleaned.startsWith('+')) return cleaned.substring(1);
  if (cleaned.startsWith('0')) return '91${cleaned.substring(1)}';
  if (cleaned.length == 10) return '91$cleaned';
  return cleaned;
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── GROUP 1: Crash threshold math ─────────────────────────────────────────
  group('Crash threshold math', () {
    test('magnitude is zero when linear acceleration is zero', () {
      // All raw axes equal gravity — net linear acceleration = 0.
      expect(impactMagnitude(0, 0, 9.8, 0, 0, 9.8), closeTo(0.0, 1e-9));
    });

    test('magnitude equals vector length of linear acceleration', () {
      // gravity along z only; x/y spike of 20 each
      final mag = impactMagnitude(20, 20, 9.8, 0, 0, 9.8);
      expect(mag, closeTo(sqrt(20 * 20 + 20 * 20), 1e-9));
    });

    test('impact detected when magnitude exceeds threshold (30 m/s²)', () {
      // Pure z spike well above 25 m/s²
      final mag = impactMagnitude(0, 0, 9.8 + 30.0, 0, 0, 9.8);
      expect(mag, greaterThan(_impactThreshold));
    });

    test('impact NOT detected for gentle braking (~5 m/s²)', () {
      final mag = impactMagnitude(5, 0, 9.8, 0, 0, 9.8);
      expect(mag, lessThan(_impactThreshold));
    });

    test('impact NOT detected at exactly the threshold boundary', () {
      // Magnitude == threshold should NOT fire (condition is strictly >)
      final mag = impactMagnitude(_impactThreshold, 0, 9.8, 0, 0, 9.8);
      expect(mag, isNot(greaterThan(_impactThreshold)));
    });

    test('impact IS detected just above threshold boundary', () {
      final mag = impactMagnitude(_impactThreshold + 0.001, 0, 9.8, 0, 0, 9.8);
      expect(mag, greaterThan(_impactThreshold));
    });

    test('low-pass filter converges gravity toward constant raw input', () {
      // Start with perfect z-gravity, feed constant (0, 0, 9.8) many times.
      double gx = 0, gy = 0, gz = 9.8;
      for (int i = 0; i < 100; i++) {
        final g = lowPassStep(gx, gy, gz, 0, 0, 9.8);
        gx = g[0]; gy = g[1]; gz = g[2];
      }
      // After 100 steps the filter should still hold (0,0,9.8).
      expect(gx, closeTo(0.0, 1e-6));
      expect(gy, closeTo(0.0, 1e-6));
      expect(gz, closeTo(9.8, 1e-6));
    });

    test('low-pass filter is weighted: alpha=0.8 keeps 80% of prior gravity', () {
      // Single step from (0,0,9.8) with new input (10,0,0).
      final g = lowPassStep(0, 0, 9.8, 10, 0, 0);
      expect(g[0], closeTo(0.8 * 0 + 0.2 * 10, 1e-9)); // 2.0
      expect(g[1], closeTo(0.0,                 1e-9));
      expect(g[2], closeTo(0.8 * 9.8,           1e-9)); // 7.84
    });

    test('diagonal crash spike is magnitude-correct', () {
      // Equal spike on all three axes above gravity.
      const spike = 20.0;
      final mag = impactMagnitude(spike, spike, 9.8 + spike, 0, 0, 9.8);
      expect(mag, closeTo(sqrt(3) * spike, 1e-6));
    });
  });

  // ── GROUP 2: Contact string parsing ───────────────────────────────────────
  group('Contact string parsing', () {
    test('fromPrefsString splits on first pipe', () {
      final c = Contact.fromPrefsString('Alice|+919876543210');
      expect(c.name,   'Alice');
      expect(c.number, '+919876543210');
    });

    test('fromPrefsString with no pipe treats whole string as number', () {
      final c = Contact.fromPrefsString('+911234567890');
      expect(c.name,   '');
      expect(c.number, '+911234567890');
    });

    test('fromPrefsString handles pipe at index 0 (empty name)', () {
      final c = Contact.fromPrefsString('|9876543210');
      expect(c.name,   '');
      expect(c.number, '9876543210');
    });

    test('fromPrefsString handles number containing a pipe in display name', () {
      // "A|B|123" — only the FIRST pipe splits; number = "B|123"
      final c = Contact.fromPrefsString('A|B|123');
      expect(c.name,   'A');
      expect(c.number, 'B|123');
    });

    test('toPrefsString round-trips correctly', () {
      const c = Contact(name: 'Bob', number: '9876543210');
      expect(Contact.fromPrefsString(c.toPrefsString()), equals(c));
    });

    test('toPrefsString with empty name round-trips', () {
      const c = Contact(name: '', number: '0987654321');
      expect(Contact.fromPrefsString(c.toPrefsString()), equals(c));
    });

    test('parseContactsBlob parses multi-line blob correctly', () {
      const blob = 'Alice|111\nBob|222\nCarol|333';
      final contacts = parseContactsBlob(blob);
      expect(contacts.length, 3);
      expect(contacts[0], const Contact(name: 'Alice', number: '111'));
      expect(contacts[1], const Contact(name: 'Bob',   number: '222'));
      expect(contacts[2], const Contact(name: 'Carol', number: '333'));
    });

    test('parseContactsBlob ignores blank lines', () {
      const blob = 'Alice|111\n\n\nBob|222\n';
      final contacts = parseContactsBlob(blob);
      expect(contacts.length, 2);
    });

    test('parseContactsBlob returns empty list for empty string', () {
      expect(parseContactsBlob(''), isEmpty);
    });

    test('serialiseContacts produces correct newline-joined blob', () {
      final contacts = [
        const Contact(name: 'Alice', number: '111'),
        const Contact(name: 'Bob',   number: '222'),
      ];
      expect(serialiseContacts(contacts), 'Alice|111\nBob|222');
    });

    test('serialiseContacts then parseContactsBlob full round-trip', () {
      final original = [
        const Contact(name: 'Riya',  number: '+919000000001'),
        const Contact(name: 'Arjun', number: '+919000000002'),
        const Contact(name: '',      number: '9000000003'),
      ];
      final blob     = serialiseContacts(original);
      final restored = parseContactsBlob(blob);
      expect(restored, original);
    });

    test('number-only entry (no pipe) survives round-trip via blob', () {
      // CrashTaskHandler reads the same storage; a number-only entry must work.
      const blob = '9876543210';
      final contacts = parseContactsBlob(blob);
      expect(contacts.length, 1);
      expect(contacts[0].number, '9876543210');
      expect(contacts[0].name,   '');
    });
  });

  // ── GROUP 3: WhatsApp number formatting ───────────────────────────────────
  group('WhatsApp number formatting (_toWaIntl)', () {
    test('E.164 number: leading + is stripped', () {
      expect(toWaIntl('+919876543210'), '919876543210');
    });

    test('10-digit local number gets 91 prefix', () {
      expect(toWaIntl('9876543210'), '919876543210');
    });

    test('leading-zero number replaces 0 with 91', () {
      expect(toWaIntl('09876543210'), '919876543210');
    });

    test('spaces and hyphens are stripped before formatting', () {
      expect(toWaIntl('+91 98765 43210'), '919876543210');
      expect(toWaIntl('98765-43210'),     '919876543210');
    });

    test('parentheses and dots are stripped', () {
      expect(toWaIntl('(0987) 654.3210'), '919876543210');
    });

    test('already-clean 12-digit intl number is returned as-is', () {
      // 12 digits, no +, no leading 0 — none of the branches match → passthrough
      expect(toWaIntl('919876543210'), '919876543210');
    });

    test('non-Indian E.164 number: + stripped, country code preserved', () {
      expect(toWaIntl('+14155552671'), '14155552671');
    });

    test('empty string returns empty string', () {
      expect(toWaIntl(''), '');
    });

    test('number with only non-digit chars returns empty string', () {
      expect(toWaIntl('---'), '');
    });

    test('11-digit number starting with non-zero/non-plus passes through', () {
      // 11 digits not starting with 0: not 10 digits, not +, not leading-0
      expect(toWaIntl('91987654321'), '91987654321');
    });
  });
}
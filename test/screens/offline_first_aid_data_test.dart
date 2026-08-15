// test/screens/offline_first_aid_data_test.dart
//
// Pure-logic unit tests for OfflineFirstAidData.find().
// No Flutter widgets, no channels — runs as fast as any plain Dart test.
//
// Run: flutter test test/screens/offline_first_aid_data_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/screens/offline_first_aid_data.dart';

void main() {
  // ── 1. Keyword matching ────────────────────────────────────────────────────
  group('OfflineFirstAidData.find() — keyword matching (English)', () {
    test('matches "bleeding" keyword', () {
      final result = OfflineFirstAidData.find(
        query: 'I am bleeding heavily',
        langCode: 'en',
      );
      expect(result, contains('BLEEDING'));
    });

    test('matches "blood" keyword', () {
      final result = OfflineFirstAidData.find(
        query: 'there is a lot of blood',
        langCode: 'en',
      );
      expect(result, contains('BLEEDING'));
    });

    test('matches "heart attack" keyword', () {
      final result = OfflineFirstAidData.find(
        query: 'symptoms of heart attack',
        langCode: 'en',
      );
      expect(result, contains('HEART ATTACK'));
    });

    test('matches "chest pain" as heart attack topic', () {
      final result = OfflineFirstAidData.find(
        query: 'chest pain on left side',
        langCode: 'en',
      );
      expect(result, contains('108/112'));
    });

    test('matches "burn" keyword', () {
      final result = OfflineFirstAidData.find(
        query: 'burn from hot water',
        langCode: 'en',
      );
      // Should not return the generic fallback
      expect(result, isNot(contains('General First Aid')));
    });

    test('matches "snake" keyword', () {
      final result = OfflineFirstAidData.find(
        query: 'snake bite on my leg',
        langCode: 'en',
      );
      expect(result, isNot(contains('General First Aid')));
    });

    test('matches "choking" keyword', () {
      final result = OfflineFirstAidData.find(
        query: 'someone is choking on food',
        langCode: 'en',
      );
      expect(result, isNot(contains('General First Aid')));
    });

    test('case-insensitive matching — uppercase query', () {
      final lower = OfflineFirstAidData.find(
        query: 'bleeding',
        langCode: 'en',
      );
      final upper = OfflineFirstAidData.find(
        query: 'BLEEDING',
        langCode: 'en',
      );
      expect(lower, equals(upper));
    });
  });

  // ── 2. Multi-language support ──────────────────────────────────────────────
  group('OfflineFirstAidData.find() — language variants', () {
    test('returns Hindi answer for bleeding with langCode "hi"', () {
      final result = OfflineFirstAidData.find(
        query: 'bleeding',
        langCode: 'hi',
      );
      // Hindi answer contains Devanagari
      expect(result, contains('रक्तस्राव'));
    });

    test('returns Telugu answer for bleeding with langCode "te"', () {
      final result = OfflineFirstAidData.find(
        query: 'bleeding',
        langCode: 'te',
      );
      expect(result, contains('రక్తస్రావం'));
    });

    test('returns Tamil answer for bleeding with langCode "ta"', () {
      final result = OfflineFirstAidData.find(
        query: 'bleeding',
        langCode: 'ta',
      );
      expect(result, contains('இரத்தப்போக்கு'));
    });

    test('returns Spanish answer for bleeding with langCode "es"', () {
      final result = OfflineFirstAidData.find(
        query: 'bleeding',
        langCode: 'es',
      );
      expect(result, contains('SANGRADO'));
    });

    test('returns English for unknown langCode', () {
      final result = OfflineFirstAidData.find(
        query: 'bleeding',
        langCode: 'xx', // non-existent
      );
      // Falls back to English
      expect(result, contains('BLEEDING'));
    });
  });

  // ── 3. Fallback / no match ─────────────────────────────────────────────────
  group('OfflineFirstAidData.find() — no match fallback', () {
    test('returns generic message when query matches no topic', () {
      final result = OfflineFirstAidData.find(
        query: 'random gibberish xyz123',
        langCode: 'en',
      );
      expect(result, contains('General First Aid'));
    });

    test('generic fallback contains 108 / 112 call instruction', () {
      final result = OfflineFirstAidData.find(
        query: 'zzz not a real emergency keyword',
        langCode: 'en',
      );
      expect(result, contains('108'));
    });

    test('generic fallback in Hindi for unmatched Hindi query', () {
      final result = OfflineFirstAidData.find(
        query: 'xyz hindi no match',
        langCode: 'hi',
      );
      expect(result, contains('सामान्य'));
    });

    test('empty query returns generic fallback', () {
      final result = OfflineFirstAidData.find(
        query: '',
        langCode: 'en',
      );
      expect(result, contains('General First Aid'));
    });
  });

  // ── 4. Answer quality ──────────────────────────────────────────────────────
  group('OfflineFirstAidData.find() — answer quality', () {
    test('bleeding answer mentions applying pressure', () {
      final result = OfflineFirstAidData.find(
        query: 'bleeding',
        langCode: 'en',
      );
      expect(result.toLowerCase(), contains('pressure'));
    });

    test('heart attack answer mentions CPR', () {
      final result = OfflineFirstAidData.find(
        query: 'heart attack',
        langCode: 'en',
      );
      expect(result, contains('CPR'));
    });

    test('all matched answers are non-empty', () {
      const queries = [
        'bleeding',
        'heart attack',
        'burn',
        'broken bone',
        'unconscious',
        'snake bite',
        'stroke',
        'seizure',
        'allergic',
        'head injury',
        'heat stroke',
        'choking',
      ];

      for (final q in queries) {
        final result = OfflineFirstAidData.find(
          query: q,
          langCode: 'en',
        );
        expect(result, isNotEmpty,
            reason: 'Expected non-empty result for query: "$q"');
      }
    });

    test('all answers contain emergency number', () {
      const queries = ['bleeding', 'heart attack', 'burn'];
      for (final q in queries) {
        final result = OfflineFirstAidData.find(
          query: q,
          langCode: 'en',
        );
        expect(result, contains('108'),
            reason: 'Answer for "$q" should contain emergency number 108');
      }
    });
  });
}

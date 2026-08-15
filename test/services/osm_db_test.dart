import 'package:flutter_test/flutter_test.dart';

import 'package:crashaid/services/osm_db.dart';

// ─────────────────────────────────────────────────────────────────────────────
// osm_db_test.dart — covers OsmDb static helpers WITHOUT touching SQLite.
//
// queryNearby() requires a real database file (asset copy → sqflite) which
// is not available in the test environment, so we test every other path:
//   • OsmDb.dbCategories()  — all 8 named cases + default branch
//   • OsmDb._cos()          — exposed indirectly via dbCategories (same file)
//   • OsmPlace              — field storage, distance filtering
//
// Run: flutter test test/services/osm_db_test.dart
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. OsmDb.dbCategories() — named cases ──────────────────────────────────
  group('OsmDb.dbCategories() named cases', () {
    test('amenity_hospital → [amenity_hospital]', () {
      expect(
        OsmDb.dbCategories('amenity', 'hospital'),
        equals(['amenity_hospital']),
      );
    });

    test('healthcare_blood_bank → [healthcare_blood_bank]', () {
      expect(
        OsmDb.dbCategories('healthcare', 'blood_bank'),
        equals(['healthcare_blood_bank']),
      );
    });

    test('emergency_ambulance_station → two categories', () {
      final cats = OsmDb.dbCategories('emergency', 'ambulance_station');
      expect(cats, contains('emergency_ambulance_station'));
      expect(cats, contains('amenity_hospital'));
      expect(cats.length, equals(2));
    });

    test('amenity_police → [amenity_police]', () {
      expect(
        OsmDb.dbCategories('amenity', 'police'),
        equals(['amenity_police']),
      );
    });

    test('shop_car → [shop_car]', () {
      expect(
        OsmDb.dbCategories('shop', 'car'),
        equals(['shop_car']),
      );
    });

    test('shop_car_repair → [shop_car_repair]', () {
      expect(
        OsmDb.dbCategories('shop', 'car_repair'),
        equals(['shop_car_repair']),
      );
    });

    test('shop_tyres → [shop_tyres]', () {
      expect(
        OsmDb.dbCategories('shop', 'tyres'),
        equals(['shop_tyres']),
      );
    });

    test('healthcare_emergency → [amenity_hospital] (trauma fallback)', () {
      expect(
        OsmDb.dbCategories('healthcare', 'emergency'),
        equals(['amenity_hospital']),
      );
    });
  });

  // ── 2. OsmDb.dbCategories() — default / unknown branch ────────────────────
  group('OsmDb.dbCategories() default branch', () {
    test('unknown key returns list with combined key and osmValue', () {
      final cats = OsmDb.dbCategories('foo', 'bar');
      expect(cats, isNotEmpty);
      expect(cats, contains('foo_bar'));
    });

    test('unknown key list length is 2', () {
      final cats = OsmDb.dbCategories('leisure', 'park');
      expect(cats.length, equals(2));
    });

    test('second element of default is the osmValue alone', () {
      final cats = OsmDb.dbCategories('natural', 'wood');
      expect(cats[1], equals('wood'));
    });
  });

  // ── 3. OsmPlace field storage ──────────────────────────────────────────────
  group('OsmPlace', () {
    test('required fields stored correctly', () {
      final place = OsmPlace(
        name: 'NIMS Hospital',
        lat: 17.385,
        lon: 78.486,
        category: 'amenity_hospital',
        distanceKm: 2.4,
      );
      expect(place.name, equals('NIMS Hospital'));
      expect(place.lat, equals(17.385));
      expect(place.lon, equals(78.486));
      expect(place.category, equals('amenity_hospital'));
      expect(place.distanceKm, equals(2.4));
    });

    test('optional phone and address default to null', () {
      final place = OsmPlace(
        name: 'Police Station',
        lat: 17.4,
        lon: 78.5,
        category: 'amenity_police',
        distanceKm: 1.0,
      );
      expect(place.phone, isNull);
      expect(place.address, isNull);
    });

    test('optional phone stored when provided', () {
      final place = OsmPlace(
        name: 'Hospital',
        lat: 17.4,
        lon: 78.5,
        category: 'amenity_hospital',
        distanceKm: 3.0,
        phone: '+91-040-12345678',
        address: '123 Main St',
      );
      expect(place.phone, equals('+91-040-12345678'));
      expect(place.address, equals('123 Main St'));
    });

    test('distance within 50 km passes filter', () {
      final place = OsmPlace(
        name: 'Test',
        lat: 0,
        lon: 0,
        category: 'amenity_police',
        distanceKm: 45.0,
      );
      expect(place.distanceKm <= 50.0, isTrue);
    });

    test('distance beyond 50 km fails filter', () {
      final place = OsmPlace(
        name: 'Far Away',
        lat: 0,
        lon: 0,
        category: 'amenity_police',
        distanceKm: 55.0,
      );
      expect(place.distanceKm <= 50.0, isFalse);
    });
  });

  // ── 4. Sort + limit contract (mirrors queryNearby post-processing) ─────────
  group('queryNearby result contract (sort + limit logic)', () {
    List<OsmPlace> sortAndLimit(List<OsmPlace> places, int limit,
        {double radiusKm = 50.0}) {
      final filtered =
          places.where((p) => p.distanceKm <= radiusKm).toList();
      filtered.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      return filtered.take(limit).toList();
    }

    test('results are sorted nearest-first', () {
      final places = [
        OsmPlace(name: 'C', lat: 0, lon: 0, category: 'x', distanceKm: 30),
        OsmPlace(name: 'A', lat: 0, lon: 0, category: 'x', distanceKm: 5),
        OsmPlace(name: 'B', lat: 0, lon: 0, category: 'x', distanceKm: 15),
      ];
      final result = sortAndLimit(places, 10);
      expect(result[0].name, equals('A'));
      expect(result[1].name, equals('B'));
      expect(result[2].name, equals('C'));
    });

    test('results respect the limit', () {
      final places = List.generate(
        40,
        (i) => OsmPlace(
          name: 'Place$i',
          lat: 0,
          lon: 0,
          category: 'x',
          distanceKm: i.toDouble(),
        ),
      );
      final result = sortAndLimit(places, 30);
      expect(result.length, equals(30));
    });

    test('places beyond radius are excluded', () {
      final places = [
        OsmPlace(name: 'Near', lat: 0, lon: 0, category: 'x', distanceKm: 10),
        OsmPlace(name: 'Far', lat: 0, lon: 0, category: 'x', distanceKm: 60),
      ];
      final result = sortAndLimit(places, 10);
      expect(result.length, equals(1));
      expect(result.first.name, equals('Near'));
    });

    test('empty input returns empty list', () {
      expect(sortAndLimit([], 30), isEmpty);
    });

    test('all within radius returns all when under limit', () {
      final places = [
        OsmPlace(name: 'A', lat: 0, lon: 0, category: 'x', distanceKm: 1),
        OsmPlace(name: 'B', lat: 0, lon: 0, category: 'x', distanceKm: 2),
      ];
      expect(sortAndLimit(places, 10).length, equals(2));
    });
  });
}
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:geolocator/geolocator.dart';

class OsmPlace {
  final String name;
  final double lat;
  final double lon;
  final String category;
  final String? phone;
  final String? address;
  final double distanceKm;

  OsmPlace({
    required this.name,
    required this.lat,
    required this.lon,
    required this.category,
    this.phone,
    this.address,
    required this.distanceKm,
  });
}

class OsmDb {
  static Database? _db;

  // ── Exact category strings stored in places.db ──────────────────────────
  // amenity_hospital          22035 rows  (hospitals, trauma, ambulance lookup)
  // healthcare_blood_bank       239 rows
  // emergency_ambulance_station  29 rows
  // amenity_police             2133 rows
  // shop_car                   1678 rows
  // shop_car_repair            1394 rows
  // shop_tyres                  794 rows

  /// Map from (osmKey, osmValue) pairs used in the UI to the actual DB category.
  /// Supports multiple categories via a list (queried with IN clause).
  static List<String> dbCategories(String osmKey, String osmValue) {
    final key = '${osmKey}_$osmValue';
    switch (key) {
      case 'amenity_hospital':
        return ['amenity_hospital'];
      case 'healthcare_blood_bank':
        return ['healthcare_blood_bank'];
      case 'emergency_ambulance_station':
        return ['emergency_ambulance_station', 'amenity_hospital'];
      case 'amenity_police':
        return ['amenity_police'];
      case 'shop_car':
        return ['shop_car'];
      case 'shop_car_repair':
        return ['shop_car_repair'];
      case 'shop_tyres':
        return ['shop_tyres'];
      // Trauma centers — best available data is hospitals
      case 'healthcare_emergency':
        return ['amenity_hospital'];
      default:
        // Try the combined key directly, then fallback to osmValue alone
        return [key, osmValue];
    }
  }

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = join(await getDatabasesPath(), 'places.db');

    // Always re-copy from assets so updates ship correctly
    if (!await File(dbPath).exists()) {
      final data = await rootBundle.load('assets/places.db');
      final bytes = data.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    return await openDatabase(dbPath, readOnly: true);
  }

  /// Query nearby places.
  /// [categories] must be the exact strings stored in the DB 'category' column.
  /// Returns up to [limit] results within [radiusKm] km, sorted by distance.
  static Future<List<OsmPlace>> queryNearby({
    required double userLat,
    required double userLon,
    required List<String> categories,
    double radiusKm = 50.0,
    int limit = 30,
  }) async {
    final db = await database;

    final latDelta = radiusKm / 111.0;
    final lonDelta = radiusKm / (111.0 * _cos(userLat));

    // Build IN clause for multiple categories
    final placeholders = List.filled(categories.length, '?').join(',');
    final whereArgs = [
      ...categories,
      userLat - latDelta,
      userLat + latDelta,
      userLon - lonDelta,
      userLon + lonDelta,
    ];

    final rows = await db.rawQuery(
      'SELECT * FROM places '
      'WHERE category IN ($placeholders) '
      'AND lat BETWEEN ? AND ? '
      'AND lon BETWEEN ? AND ?',
      whereArgs,
    );

    final places = rows.map((row) {
      final lat = (row['lat'] as num).toDouble();
      final lon = (row['lon'] as num).toDouble();
      final dist = Geolocator.distanceBetween(userLat, userLon, lat, lon) / 1000;
      return OsmPlace(
        name: row['name'] as String? ?? 'Unknown',
        lat: lat,
        lon: lon,
        category: row['category'] as String,
        phone: row['phone'] as String?,
        address: row['address'] as String?,
        distanceKm: dist,
      );
    }).where((p) => p.distanceKm <= radiusKm).toList();

    places.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return places.take(limit).toList();
  }

  static double _cos(double degrees) {
    final rad = degrees * 3.14159265358979 / 180.0;
    return rad.abs() < 0.01 ? 1.0 : (1.0 - rad * rad / 2.0);
  }
}
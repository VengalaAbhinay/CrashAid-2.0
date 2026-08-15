import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Lightweight sqflite mirror of the emergency contacts list.
///
/// The source of truth for contact data is FlutterSecureStorage (AES-encrypted).
/// This table is a plaintext mirror so the background isolate
/// (crash_foreground_service.dart) can read contacts without needing
/// flutter_secure_storage, which cannot be used in a non-UI isolate.
///
/// Write flow:  ContactsScreen  →  SecureStorage (encrypted, primary)
///                              →  ContactsDb    (sqflite, background-readable)
/// Read flow:   UI              →  SecureStorage
///              Background      →  ContactsDb
class ContactsDb {
  ContactsDb._();
  static final ContactsDb instance = ContactsDb._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'crashaid_contacts.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE contacts (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            uid     TEXT    NOT NULL,
            name    TEXT    NOT NULL DEFAULT '',
            number  TEXT    NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_contacts_uid ON contacts (uid)');
      },
    );
  }

  // ── Write helpers (called from ContactsScreen) ──────────────────────────

  /// Replaces ALL contacts for [uid] with [contacts].
  /// Pass a list of maps with keys 'name' and 'number'.
  Future<void> replaceAll(String uid, List<Map<String, String>> contacts) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('contacts', where: 'uid = ?', whereArgs: [uid]);
      for (final c in contacts) {
        await txn.insert('contacts', {
          'uid': uid,
          'name': c['name'] ?? '',
          'number': c['number'] ?? '',
        });
      }
    });
  }

  // ── Read helpers (called from background isolate) ────────────────────────

  /// Returns all phone numbers for [uid].
  /// If [uid] is null or empty, falls back to reading whichever uid has rows.
  Future<List<String>> readNumbers(String? uid) async {
    final db = await database;
    List<Map<String, dynamic>> rows;

    if (uid != null && uid.isNotEmpty && uid != 'guest') {
      rows = await db.query('contacts',
          columns: ['number'], where: 'uid = ?', whereArgs: [uid]);
    } else {
      // Background isolate may not have auth context — grab whatever is stored
      rows = await db.query('contacts', columns: ['number']);
    }

    return rows
        .map((r) => (r['number'] as String).trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  /// Returns full contact rows [{name, number}] for [uid].
  Future<List<Map<String, String>>> readContacts(String uid) async {
    final db = await database;
    final rows = await db.query('contacts',
        columns: ['name', 'number'],
        where: 'uid = ?',
        whereArgs: [uid]);
    return rows
        .map((r) => {
              'name': r['name'] as String,
              'number': r['number'] as String,
            })
        .toList();
  }

  // ── Teardown (tests / logout) ────────────────────────────────────────────

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> deleteAll(String uid) async {
    final db = await database;
    await db.delete('contacts', where: 'uid = ?', whereArgs: [uid]);
  }
}
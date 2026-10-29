import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static Future<Database> open(String path, {DatabaseFactory? factory}) {
    final options = OpenDatabaseOptions(version: 2, onCreate: _create, onUpgrade: _upgrade);
    return (factory ?? databaseFactory).openDatabase(path, options: options);
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('ALTER TABLE attendance_events ADD COLUMN reject_code TEXT');
      await _createLeaveOutbox(db);
    }
  }

  static Future<void> _createLeaveOutbox(Database db) => db.execute('''
    CREATE TABLE leave_outbox (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      reason TEXT NOT NULL,
      status TEXT NOT NULL,
      last_error TEXT,
      attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )''');

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE attendance_events (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        work_date TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        uncertain INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT,
        reject_code TEXT
      )''');
    await db.execute('''
      CREATE UNIQUE INDEX ux_event_day_type
      ON attendance_events (employee_id, work_date, type)
      WHERE status != 'rejected' ''');
    await db.execute('''
      CREATE TABLE attendance_days (
        date TEXT PRIMARY KEY,
        check_in TEXT,
        check_out TEXT
      )''');
    await db.execute('''
      CREATE TABLE cache (
        key TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )''');
    await _createLeaveOutbox(db);
  }
}

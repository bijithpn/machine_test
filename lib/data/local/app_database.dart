import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static Future<Database> open(String path, {DatabaseFactory? factory}) {
    final options = OpenDatabaseOptions(version: 1, onCreate: _create);
    return (factory ?? databaseFactory).openDatabase(path, options: options);
  }

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
        next_attempt_at TEXT
      )''');
    // Backstop for the domain rule: at most one live event of each type per day.
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
  }
}

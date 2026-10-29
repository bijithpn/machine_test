import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class Cached<T> {
  const Cached(this.value, this.fetchedAt);
  final T value;
  final DateTime fetchedAt;
}

class CacheStore {
  CacheStore(this._db);
  final Database _db;

  Future<Cached<Object?>?> read(String key) async {
    final rows = await _db.query('cache', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return Cached(jsonDecode(rows.first['json']! as String), DateTime.parse(rows.first['fetched_at']! as String));
  }

  Future<void> write(String key, Object? value, DateTime now) => _db.insert('cache', {
    'key': key,
    'json': jsonEncode(value),
    'fetched_at': now.toUtc().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

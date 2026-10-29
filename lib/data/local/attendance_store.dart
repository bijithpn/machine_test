import 'package:sqflite/sqflite.dart';

import '../../core/errors/exceptions.dart';
import '../../domain/attendance_rules.dart';
import '../../domain/models.dart';

class AttendanceStore {
  AttendanceStore(this._db);
  final Database _db;

  AttendanceEvent _event(Map<String, Object?> r) => AttendanceEvent(
    id: r['id']! as String,
    employeeId: r['employee_id']! as String,
    type: AttendanceType.fromWire(r['type']! as String),
    timestamp: DateTime.parse(r['timestamp']! as String),
    workDate: r['work_date']! as String,
    latitude: r['latitude']! as double,
    longitude: r['longitude']! as double,
    status: SyncStatus.values.byName(r['status']! as String),
    attempts: r['attempts']! as int,
    lastError: r['last_error'] as String?,
    uncertain: (r['uncertain']! as int) == 1,
    nextAttemptAt: r['next_attempt_at'] == null ? null : DateTime.parse(r['next_attempt_at']! as String),
  );

  /// Server history overlaid with local events. Pending and synced events fill
  /// gaps in the cached day, so a stale refresh can never hide a local action.
  Future<Map<String, AttendanceDay>> _mergedDays(DatabaseExecutor db) async {
    final days = <String, ({DateTime? inAt, DateTime? outAt, SyncStatus sync, String? reason})>{};
    for (final r in await db.query('attendance_days')) {
      days[r['date']! as String] = (
        inAt: _parse(r['check_in']),
        outAt: _parse(r['check_out']),
        sync: SyncStatus.synced,
        reason: null,
      );
    }
    final events = await db.query('attendance_events', orderBy: 'timestamp, rowid');
    for (final e in events.map(_event)) {
      final cur = days[e.workDate] ?? (inAt: null, outAt: null, sync: SyncStatus.synced, reason: null);
      var sync = cur.sync;
      var reason = cur.reason;
      var inAt = cur.inAt;
      var outAt = cur.outAt;
      switch (e.status) {
        case SyncStatus.rejected:
          sync = SyncStatus.rejected;
          reason = e.lastError;
        case SyncStatus.pending:
          if (sync != SyncStatus.rejected) sync = SyncStatus.pending;
          if (e.type == AttendanceType.checkIn)
            inAt ??= e.timestamp;
          else
            outAt ??= e.timestamp;
        case SyncStatus.synced:
          if (e.type == AttendanceType.checkIn)
            inAt ??= e.timestamp;
          else
            outAt ??= e.timestamp;
      }
      days[e.workDate] = (inAt: inAt, outAt: outAt, sync: sync, reason: reason);
    }
    return {
      for (final entry in days.entries)
        entry.key: AttendanceDay(
          date: entry.key,
          checkIn: entry.value.inAt,
          checkOut: entry.value.outAt,
          sync: entry.value.sync,
          rejectionReason: entry.value.reason,
        ),
    };
  }

  DateTime? _parse(Object? v) => v == null ? null : DateTime.parse(v as String);

  Future<AttendanceDay?> day(String date) async => (await _mergedDays(_db))[date];

  Future<List<AttendanceDay>> days({int? limit, String? monthPrefix}) async {
    final all = (await _mergedDays(_db)).values.where((d) => monthPrefix == null || d.date.startsWith(monthPrefix));
    final sorted = all.toList()..sort((a, b) => b.date.compareTo(a.date));
    return limit == null ? sorted : sorted.take(limit).toList();
  }

  Future<void> insertEvent(AttendanceEvent event) => _db.transaction((txn) async {
    final today = (await _mergedDays(txn))[event.workDate];
    AttendanceRules.ensureAllowed(event.type, today);
    try {
      await txn.insert('attendance_events', {
        'id': event.id,
        'employee_id': event.employeeId,
        'type': event.type.wire,
        'timestamp': event.timestamp.toUtc().toIso8601String(),
        'work_date': event.workDate,
        'latitude': event.latitude,
        'longitude': event.longitude,
        'status': SyncStatus.pending.name,
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const AttendanceRuleException('That attendance action is already recorded.');
      }
      rethrow;
    }
  });

  Future<List<AttendanceEvent>> pendingEvents() async => (await _db.query(
    'attendance_events',
    where: 'status = ?',
    whereArgs: [SyncStatus.pending.name],
    orderBy: 'timestamp, rowid',
  )).map(_event).toList();

  Future<List<AttendanceEvent>> recentEvents({int limit = 30}) async =>
      (await _db.query('attendance_events', orderBy: 'timestamp DESC, rowid DESC', limit: limit)).map(_event).toList();

  Future<SyncCounts> counts() async {
    final rows = await _db.rawQuery('SELECT status, COUNT(*) AS n FROM attendance_events GROUP BY status');
    int n(SyncStatus s) => rows.where((r) => r['status'] == s.name).map((r) => r['n']! as int).firstOrNull ?? 0;
    return SyncCounts(pending: n(SyncStatus.pending), synced: n(SyncStatus.synced), rejected: n(SyncStatus.rejected));
  }

  Future<void> markSynced(String id) => _db.update(
    'attendance_events',
    {'status': SyncStatus.synced.name, 'last_error': null, 'uncertain': 0, 'next_attempt_at': null},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> markRejected(String id, String reason) => _db.update(
    'attendance_events',
    {'status': SyncStatus.rejected.name, 'last_error': reason, 'uncertain': 0, 'next_attempt_at': null},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> markAttemptFailed(
    String id, {
    required String error,
    required bool uncertain,
    required DateTime nextAttemptAt,
  }) => _db.rawUpdate(
    'UPDATE attendance_events SET attempts = attempts + 1, last_error = ?, uncertain = ?, next_attempt_at = ? WHERE id = ?',
    [error, uncertain ? 1 : 0, nextAttemptAt.toUtc().toIso8601String(), id],
  );

  Future<void> replaceMonth(String month, List<({String date, DateTime? checkIn, DateTime? checkOut})> records) =>
      _db.transaction((txn) async {
        await txn.delete('attendance_days', where: 'date LIKE ?', whereArgs: ['$month-%']);
        for (final r in records) {
          await txn.insert('attendance_days', {
            'date': r.date,
            'check_in': r.checkIn?.toUtc().toIso8601String(),
            'check_out': r.checkOut?.toUtc().toIso8601String(),
          });
        }
      });
}

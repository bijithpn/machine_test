import 'package:sqflite/sqflite.dart';

import '../../core/time/company_clock.dart';
import '../../domain/models.dart';

class LeaveOutboxStore {
  LeaveOutboxStore(this._db);
  final Database _db;

  QueuedLeave _row(Map<String, Object?> r) => QueuedLeave(
    id: r['id']! as String,
    draft: LeaveDraft(
      type: LeaveType.values.byName(r['type']! as String),
      start: CompanyClock.parseDate(r['start_date']! as String),
      end: CompanyClock.parseDate(r['end_date']! as String),
      reason: r['reason']! as String,
    ),
    status: SyncStatus.values.byName(r['status']! as String),
    createdAt: DateTime.parse(r['created_at']! as String),
    lastError: r['last_error'] as String?,
  );

  Future<void> insert(String id, LeaveDraft draft, DateTime now) => _db.insert('leave_outbox', {
    'id': id,
    'type': draft.type.name,
    'start_date': CompanyClock.formatDate(draft.start!),
    'end_date': CompanyClock.formatDate(draft.end!),
    'reason': draft.reason.trim(),
    'status': SyncStatus.pending.name,
    'created_at': now.toUtc().toIso8601String(),
  });

  Future<List<QueuedLeave>> all() async =>
      (await _db.query('leave_outbox', orderBy: 'created_at, rowid')).map(_row).toList();

  Future<List<QueuedLeave>> pending() async => (await all()).where((q) => q.status == SyncStatus.pending).toList();

  Future<void> delete(String id) => _db.delete('leave_outbox', where: 'id = ?', whereArgs: [id]);

  Future<void> markRejected(String id, String reason) => _db.update(
    'leave_outbox',
    {'status': SyncStatus.rejected.name, 'last_error': reason},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> markAttemptFailed(String id, String error) =>
      _db.rawUpdate('UPDATE leave_outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?', [error, id]);
}

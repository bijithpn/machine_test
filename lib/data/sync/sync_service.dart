import 'dart:math' as math;

import '../../core/time/company_clock.dart';
import '../../domain/models.dart';
import '../local/attendance_store.dart';
import '../remote/hrms_api.dart';

class SyncReport {
  const SyncReport({required this.counts, this.sent = 0, this.blockedByFailure = false});
  final SyncCounts counts;
  final int sent;
  final bool blockedByFailure;
}

class SyncService {
  SyncService(this._store, this._api, this._clock);

  static const maxAutoAttempts = 8;

  final AttendanceStore _store;
  final HrmsApi _api;
  final CompanyClock _clock;
  Future<SyncReport>? _running;

  /// Joins an in-flight run instead of starting a second one, so an event is
  /// never submitted by two runs at once. [manual] ignores backoff.
  Future<SyncReport> sync({bool manual = false}) => _running ??= _run(manual).whenComplete(() => _running = null);

  static Duration backoff(int attempts) => Duration(seconds: math.min(300, 2 << math.min(attempts, 8)));

  Future<SyncReport> _run(bool manual) async {
    var sent = 0;
    var blocked = false;
    for (final event in await _store.pendingEvents()) {
      final due = event.nextAttemptAt;
      if (!manual && ((due != null && due.isAfter(_clock.nowUtc())) || event.attempts >= maxAutoAttempts)) {
        blocked = true;
        break;
      }
      final result = await _api.sendEvent(event);
      switch (result) {
        case EventAccepted():
          await _store.markSynced(event.id);
          sent++;
        case EventRejected(:final reason):
          await _store.markRejected(event.id, reason);
        case EventTransientFailure(:final message, :final uncertain):
          await _store.markAttemptFailed(
            event.id,
            error: uncertain ? '$message; the server may have received it' : message,
            uncertain: uncertain,
            nextAttemptAt: _clock.nowUtc().add(backoff(event.attempts + 1)),
          );
          // Later events depend on this one (check-in before check-out), so stop.
          blocked = true;
      }
      if (blocked) break;
    }
    return SyncReport(counts: await _store.counts(), sent: sent, blockedByFailure: blocked);
  }
}

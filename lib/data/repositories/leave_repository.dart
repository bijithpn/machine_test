import 'package:uuid/uuid.dart';

import '../../core/errors/exceptions.dart';
import '../../core/time/company_clock.dart';
import '../../domain/leave_rules.dart';
import '../../domain/models.dart';
import '../local/cache_store.dart';
import '../local/leave_outbox_store.dart';
import '../remote/hrms_api.dart';

class LeaveSnapshot {
  const LeaveSnapshot({this.balance, this.requests = const [], this.queued = const [], this.fetchedAt});
  final int? balance;
  final List<LeaveRequest> requests;
  final List<QueuedLeave> queued;
  final DateTime? fetchedAt;

  bool get hasData => balance != null;
  int get pendingQueued => queued.where((q) => q.status == SyncStatus.pending).length;

  int? get available {
    final b = balance;
    if (b == null) return null;
    return b - queued.where((q) => q.status == SyncStatus.pending).fold(0, (sum, q) => sum + q.days);
  }

  List<LeaveRequest> get blocking => [
    ...requests,
    for (final q in queued.where((q) => q.status == SyncStatus.pending)) q.asRequest(),
  ];
}

enum LeaveSubmitResult { sent, queued }

class LeaveRepository {
  LeaveRepository(this._api, this._cache, this._outbox, this._clock);
  final HrmsApi _api;
  final CacheStore _cache;
  final LeaveOutboxStore _outbox;
  final CompanyClock _clock;
  final _uuid = const Uuid();
  var _submitting = false;
  Future<void>? _syncing;

  static const _balanceKey = 'leave.balance';
  static const _requestsKey = 'leave.requests';

  Future<LeaveSnapshot> cached() async {
    final balance = await _cache.read(_balanceKey);
    final requests = await _cache.read(_requestsKey);
    return LeaveSnapshot(
      balance: balance?.value as int?,
      requests: [
        for (final r in (requests?.value as List? ?? const []).cast<Map<String, dynamic>>()) LeaveRequest.fromJson(r),
      ],
      queued: await _outbox.all(),
      fetchedAt: balance?.fetchedAt,
    );
  }

  Future<LeaveSnapshot> refresh() async {
    await syncQueued();
    final results = await Future.wait([_api.leaveBalance(), _api.leaveRequests()]);
    final now = _clock.nowUtc();
    await _cache.write(_balanceKey, results[0] as int, now);
    await _cache.write(_requestsKey, [for (final r in results[1] as List<LeaveRequest>) r.toJson()], now);
    return cached();
  }

  Future<void> syncQueued() => _syncing ??= _syncQueued().whenComplete(() => _syncing = null);

  Future<void> _syncQueued() async {
    for (final item in await _outbox.pending()) {
      try {
        await _api.submitLeave(item.draft, requestId: item.id);
        await _outbox.delete(item.id);
      } on LeaveValidationException catch (e) {
        await _outbox.markRejected(item.id, _describe(e));
      } on ApiException catch (e) {
        await _outbox.markAttemptFailed(item.id, e.message);
        return;
      }
    }
  }

  String _describe(LeaveValidationException e) {
    final fields = e.fieldErrors.values.join('. ');
    return fields.isNotEmpty ? fields : e.message ?? 'Rejected by the server';
  }

  Future<LeaveSubmitResult> submit(LeaveDraft draft) async {
    if (_submitting) throw const ApiException('A leave request is already being submitted.');
    _submitting = true;
    try {
      final snapshot = await cached();
      final available = snapshot.available;
      if (available == null)
        throw const OfflineException('Leave balance has not loaded yet. Connect and refresh first.');
      final errors = LeaveRules.validate(
        draft: draft,
        today: _clock.todayDate,
        balance: available,
        existing: snapshot.blocking,
      );
      if (errors.isNotEmpty) throw LeaveValidationException(errors);

      final id = _uuid.v4();
      await _outbox.insert(id, draft, _clock.nowUtc());
      try {
        await _api.submitLeave(draft, requestId: id);
      } on LeaveValidationException {
        await _outbox.delete(id);
        rethrow;
      } on ApiException {
        return LeaveSubmitResult.queued;
      }
      await _outbox.delete(id);
      await refresh().then<void>((_) {}, onError: (_) {});
      return LeaveSubmitResult.sent;
    } finally {
      _submitting = false;
    }
  }

  Future<void> dismiss(String id) => _outbox.delete(id);
}

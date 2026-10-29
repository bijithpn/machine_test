import '../../core/errors/exceptions.dart';
import '../../core/time/company_clock.dart';
import '../../domain/leave_rules.dart';
import '../../domain/models.dart';
import '../local/cache_store.dart';
import '../remote/hrms_api.dart';

class LeaveSnapshot {
  const LeaveSnapshot({this.balance, this.requests = const [], this.fetchedAt});
  final int? balance;
  final List<LeaveRequest> requests;
  final DateTime? fetchedAt;
  bool get hasData => balance != null;
}

class LeaveRepository {
  LeaveRepository(this._api, this._cache, this._clock);
  final HrmsApi _api;
  final CacheStore _cache;
  final CompanyClock _clock;
  var _submitting = false;

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
      fetchedAt: balance?.fetchedAt,
    );
  }

  Future<LeaveSnapshot> refresh() async {
    final results = await Future.wait([_api.leaveBalance(), _api.leaveRequests()]);
    final now = _clock.nowUtc();
    final balance = results[0] as int;
    final requests = results[1] as List<LeaveRequest>;
    await _cache.write(_balanceKey, balance, now);
    await _cache.write(_requestsKey, [for (final r in requests) r.toJson()], now);
    return LeaveSnapshot(balance: balance, requests: requests, fetchedAt: now);
  }

  Future<LeaveRequest> submit(LeaveDraft draft) async {
    if (_submitting) throw const ApiException('A leave request is already being submitted.');
    _submitting = true;
    try {
      final snapshot = await cached();
      final balance = snapshot.balance;
      if (balance == null) throw const OfflineException('Leave balance has not loaded yet. Connect and refresh first.');
      final errors = LeaveRules.validate(
        draft: draft,
        today: _clock.todayDate,
        balance: balance,
        existing: snapshot.requests,
      );
      if (errors.isNotEmpty) throw LeaveValidationException(errors);

      try {
        final created = await _api.submitLeave(draft);
        await refresh().then<void>((_) {}, onError: (_) {});
        return created;
      } on ApiException catch (e) {
        if (HrmsApi.isConnectivityFailure(e)) throw const OfflineException();
        rethrow;
      }
    } finally {
      _submitting = false;
    }
  }
}

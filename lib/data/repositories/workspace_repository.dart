import '../../core/errors/exceptions.dart';
import '../../core/time/company_clock.dart';
import '../../domain/models.dart';
import '../local/attendance_store.dart';
import '../local/cache_store.dart';
import '../remote/hrms_api.dart';

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    this.employee,
    this.balance,
    this.today,
    this.days = const [],
    this.events = const [],
    this.counts = const SyncCounts(),
    this.updatedAt,
  });
  final Employee? employee;
  final int? balance;
  final AttendanceDay? today;
  final List<AttendanceDay> days;
  final List<AttendanceEvent> events;
  List<AttendanceDay> get recent => days.take(5).toList();
  final SyncCounts counts;
  final DateTime? updatedAt;
}

class WorkspaceRepository {
  WorkspaceRepository(this._api, this._cache, this._attendance, this._clock);
  final HrmsApi _api;
  final CacheStore _cache;
  final AttendanceStore _attendance;
  final CompanyClock _clock;

  static const _employeeKey = 'employee';
  static const _balanceKey = 'leave.balance';
  static const _updatedKey = 'workspace.updated';

  Future<WorkspaceSnapshot> local() async {
    final employee = await _cache.read(_employeeKey);
    final balance = await _cache.read(_balanceKey);
    final updated = await _cache.read(_updatedKey);
    return WorkspaceSnapshot(
      employee: employee == null ? null : Employee.fromJson(employee.value! as Map<String, dynamic>),
      balance: balance?.value as int?,
      today: await _attendance.day(_clock.today),
      days: await _attendance.days(),
      events: await _attendance.recentEvents(limit: 20),
      counts: await _attendance.counts(),
      updatedAt: updated?.fetchedAt,
    );
  }

  Future<int> clearRejected() => _attendance.clearRejected();

  Future<Office?> cachedOffice() async {
    final employee = await _cache.read(_employeeKey);
    return employee == null ? null : Employee.fromJson(employee.value! as Map<String, dynamic>).office;
  }

  Future<void> refresh() async {
    final now = _clock.nowUtc();
    final today = _clock.todayDate;
    final thisMonth = _month(today);
    final prevMonth = _month(DateTime.utc(today.year, today.month - 1));

    Object? failure;
    Future<void> step(Future<void> Function() body) async {
      try {
        await body();
      } on ApiException catch (e) {
        failure ??= e;
      }
    }

    await Future.wait([
      step(() async => _cache.write(_employeeKey, (await _api.employee()).toJson(), now)),
      step(() async => _cache.write(_balanceKey, await _api.leaveBalance(), now)),
      step(() async => _attendance.replaceMonth(thisMonth, await _api.attendanceMonth(thisMonth))),
      step(() async => _attendance.replaceMonth(prevMonth, await _api.attendanceMonth(prevMonth))),
    ]);
    if (failure == null) {
      await _attendance.requeueMissingOnServer({thisMonth, prevMonth});
      await _cache.write(_updatedKey, null, now);
    }
    if (failure != null) throw failure!;
  }

  String _month(DateTime d) => CompanyClock.formatDate(d).substring(0, 7);
}

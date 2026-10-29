import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/exceptions.dart';
import '../../core/time/company_clock.dart';
import '../../domain/attendance_rules.dart';
import '../../domain/models.dart';
import '../local/attendance_store.dart';
import '../location/location_service.dart';

class AttendanceService {
  AttendanceService(
    this._store,
    this._location,
    this._clock, {
    required this.employeeId,
    required this.officeLatitude,
    required this.officeLongitude,
    this.radiusMeters = AppConfig.officeRadiusMeters,
    this.officeOverride,
    this.serverOffice,
  });

  final AttendanceStore _store;
  final LocationService _location;
  final CompanyClock _clock;
  final String employeeId;
  final double officeLatitude;
  final double officeLongitude;
  final double radiusMeters;
  final LocationFix? Function()? officeOverride;
  final Future<Office?> Function()? serverOffice;
  final _uuid = const Uuid();
  Future<void> _tail = Future.value();

  Future<T> _locked<T>(Future<T> Function() body) {
    final result = _tail.then((_) => body());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<AttendanceEvent> record(AttendanceType type) => _locked(() async {
    final date = _clock.today;
    AttendanceRules.ensureAllowed(type, await _store.day(date));

    final fix = await _location.currentFix();
    final server = await serverOffice?.call();
    final override = officeOverride?.call();
    final limit = server?.radiusMeters ?? radiusMeters;
    final distance = AttendanceRules.distanceMeters(
      fix.latitude,
      fix.longitude,
      override?.latitude ?? server?.latitude ?? officeLatitude,
      override?.longitude ?? server?.longitude ?? officeLongitude,
    );
    if (distance > limit) throw OutsideOfficeException(distance, limit);

    final now = _clock.nowUtc();
    final event = AttendanceEvent(
      id: _uuid.v4(),
      employeeId: employeeId,
      type: type,
      timestamp: now,
      workDate: _clock.dateOf(now),
      latitude: fix.latitude,
      longitude: fix.longitude,
    );
    await _store.insertEvent(event);
    return event;
  });
}

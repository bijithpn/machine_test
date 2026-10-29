import 'package:flutter_test/flutter_test.dart';
import 'package:rebs_hrms/core/errors/exceptions.dart';
import 'package:rebs_hrms/data/repositories/attendance_service.dart';
import 'package:rebs_hrms/domain/models.dart';

import '../support/fakes.dart';

void main() {
  late SyncHarness h;
  late FakeLocation location;
  late AttendanceService service;

  setUp(() async {
    h = await SyncHarness.create();
    location = FakeLocation();
    service = AttendanceService(
      h.store,
      location,
      h.clockHolder.clock,
      employeeId: 'EMP-1042',
      officeLatitude: officeLat,
      officeLongitude: officeLng,
    );
  });

  test('check-out without check-in is rejected and nothing is stored', () async {
    await expectLater(service.record(AttendanceType.checkOut), throwsA(isA<AttendanceRuleException>()));
    expect(await h.store.recentEvents(), isEmpty);
    expect(location.calls, 0, reason: 'rules run before GPS is requested');
  });

  test('repeated and concurrent submissions create exactly one event', () async {
    location.delay = const Duration(milliseconds: 20);
    final results = await Future.wait([
      service.record(AttendanceType.checkIn).then<Object>((e) => e).catchError((Object e) => e),
      service.record(AttendanceType.checkIn).then<Object>((e) => e).catchError((Object e) => e),
      service.record(AttendanceType.checkIn).then<Object>((e) => e).catchError((Object e) => e),
    ]);
    expect(results.whereType<AttendanceEvent>(), hasLength(1));
    expect(results.whereType<AttendanceRuleException>(), hasLength(2));
    expect(await h.store.recentEvents(), hasLength(1));
  });

  test('sequence check-in then check-out is allowed once; a third action is refused', () async {
    await service.record(AttendanceType.checkIn);
    h.clockHolder.now = h.clockHolder.now.add(const Duration(hours: 8));
    await service.record(AttendanceType.checkOut);
    final today = await h.store.day(h.clockHolder.clock.today);
    expect(today!.status, AttendanceStatus.checkedOut);
    await expectLater(service.record(AttendanceType.checkOut), throwsA(isA<AttendanceRuleException>()));
    await expectLater(service.record(AttendanceType.checkIn), throwsA(isA<AttendanceRuleException>()));
  });

  test('outside the 200 m radius is refused with the measured distance', () async {
    location.lat = officeLat + 0.01;
    final err = await service.record(AttendanceType.checkIn).then<Object>((_) => 'ok').catchError((Object e) => e);
    expect(err, isA<OutsideOfficeException>());
    expect((err as OutsideOfficeException).distanceMeters, closeTo(1112, 20));
    expect(await h.store.recentEvents(), isEmpty);
  });

  test('just inside the radius is accepted', () async {
    location.lat = officeLat + 0.0017; // ~189 m
    await service.record(AttendanceType.checkIn);
    expect(await h.store.recentEvents(), hasLength(1));
  });

  test('location failures surface as LocationException and store nothing', () async {
    location.error = const LocationException(LocationFailure.deniedForever, 'blocked');
    await expectLater(
      service.record(AttendanceType.checkIn),
      throwsA(isA<LocationException>().having((e) => e.failure, 'failure', LocationFailure.deniedForever)),
    );
    expect(await h.store.recentEvents(), isEmpty);
  });

  test('a rejected check-in no longer blocks a new attempt', () async {
    final event = await service.record(AttendanceType.checkIn);
    await h.store.markRejected(event.id, 'Simulated');
    await service.record(AttendanceType.checkIn);
    final events = await h.store.recentEvents();
    expect(events, hasLength(2));
    expect(events.map((e) => e.status), containsAll([SyncStatus.rejected, SyncStatus.pending]));
  });

  test('company date follows the configured timezone, not UTC', () async {
    h.clockHolder.now = DateTime.utc(2026, 10, 27, 20); // 01:30 IST on the 28th
    final event = await service.record(AttendanceType.checkIn);
    expect(event.workDate, '2026-10-28');
  });
}

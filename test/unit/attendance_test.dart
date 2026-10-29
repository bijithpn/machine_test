import 'package:flutter_test/flutter_test.dart';
import 'package:rebs_hrms/core/errors/exceptions.dart';
import 'package:rebs_hrms/data/location/location_service.dart';
import 'package:rebs_hrms/data/repositories/attendance_service.dart';
import 'package:rebs_hrms/domain/attendance_rules.dart';
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

  test('distance is shown in metres below 1 km and in km above', () {
    expect(formatDistance(850), '850 m');
    expect(formatDistance(33333), '33.3 km');
    expect(formatDistance(999.6), '1.0 km');
    expect(formatDistance(1000), '1.0 km');
    expect(formatDistance(0), '0 m');
    expect(const OutsideOfficeException(33333, 200).message, contains('33.3 km'));
  });

  test('haversine matches known distances', () {
    double d(double a, double b, double c, double e) => AttendanceRules.distanceMeters(a, b, c, e);
    expect(d(12.9716, 77.5946, 12.9716, 77.5946), 0);
    expect(d(0, 0, 0.01, 0), closeTo(1111.95, 0.5));
    expect(d(12.9716, 77.5946, 13.5, 77.5946) / 1000, closeTo(58.755, 0.01));
    expect(d(0, 0, 0, 180), closeTo(20015087, 5));
  });

  test('the office published by the server wins over the built-in default', () async {
    location.lat = officeLat + 0.3;
    final synced = AttendanceService(
      h.store,
      location,
      h.clockHolder.clock,
      employeeId: 'EMP-1042',
      officeLatitude: officeLat,
      officeLongitude: officeLng,
      serverOffice: () async => Office(latitude: officeLat + 0.3, longitude: officeLng, radiusMeters: 200),
    );
    expect((await synced.record(AttendanceType.checkIn)).type, AttendanceType.checkIn);
  });

  test('a rejected event no longer marks the day once a live event of that type exists', () async {
    final today = h.clockHolder.clock.today;
    final first = await service.record(AttendanceType.checkIn);
    await h.store.markRejected(first.id, 'Outside the office area');
    expect((await h.store.day(today))!.sync, SyncStatus.rejected);
    await service.record(AttendanceType.checkIn);
    expect((await h.store.day(today))!.sync, SyncStatus.pending);
    expect(await h.store.clearRejected(), 1);
    expect((await h.store.counts()).rejected, 0);
    expect((await h.store.counts()).pending, 1);
  });

  test('an office override moves the geofence so a far-away location is accepted', () async {
    location.lat = officeLat + 0.3;
    await expectLater(service.record(AttendanceType.checkIn), throwsA(isA<OutsideOfficeException>()));
    final moved = AttendanceService(
      h.store,
      location,
      h.clockHolder.clock,
      employeeId: 'EMP-1042',
      officeLatitude: officeLat,
      officeLongitude: officeLng,
      officeOverride: () => LocationFix(officeLat + 0.3, officeLng),
    );
    expect((await moved.record(AttendanceType.checkIn)).type, AttendanceType.checkIn);
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rebs_hrms/data/repositories/attendance_service.dart';
import 'package:rebs_hrms/domain/models.dart';
import 'package:path/path.dart' as p;

import '../support/fakes.dart';

AttendanceService serviceFor(SyncHarness h) => AttendanceService(
  h.store,
  FakeLocation(),
  h.clockHolder.clock,
  employeeId: 'EMP-1042',
  officeLatitude: officeLat,
  officeLongitude: officeLng,
);

Future<(AttendanceEvent, AttendanceEvent)> recordDay(SyncHarness h) async {
  final service = serviceFor(h);
  final inEvent = await service.record(AttendanceType.checkIn);
  h.clockHolder.now = h.clockHolder.now.add(const Duration(hours: 8));
  final outEvent = await service.record(AttendanceType.checkOut);
  return (inEvent, outEvent);
}

void main() {
  test('pending events survive a database reload and sync in chronological order', () async {
    final dir = await Directory.systemTemp.createTemp('rebs_db');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'test.db');

    var h = await SyncHarness.create(db: await openTestDb(path));
    final (checkIn, checkOut) = await recordDay(h);
    final clock = h.clockHolder;
    await h.db.close();

    h = await SyncHarness.create(db: await openTestDb(path), clock: clock);
    final pending = await h.store.pendingEvents();
    expect(pending.map((e) => e.id), [checkIn.id, checkOut.id]);

    final report = await h.sync.sync();
    expect(report.counts.synced, 2);
    expect(report.counts.pending, 0);
    expect(h.server.order, ['check_in:${checkIn.id}', 'check_out:${checkOut.id}']);
  });

  test('a timeout after the server accepted retries idempotently with the same event id', () async {
    final h = await SyncHarness.create();
    final (checkIn, _) = await recordDay(h);
    h.server.dropNextResponseAfterCommit = true;

    final first = await h.sync.sync();
    expect(first.blockedByFailure, isTrue);
    var events = await h.store.pendingEvents();
    expect(events, hasLength(2), reason: 'a timeout must not reject or drop anything');
    expect(events.first.uncertain, isTrue);
    expect(events.first.status, SyncStatus.pending);
    expect(events.first.attempts, 1);

    final second = await h.sync.sync(manual: true);
    expect(second.counts.synced, 2);
    expect(second.counts.rejected, 0);
    expect(h.server.processed.length, 2, reason: 'server stored each event once');
    expect(h.server.sentEventIds.where((id) => id == checkIn.id), hasLength(2), reason: 'same id on retry');
  });

  test('a definitive duplicate-attendance conflict is rejected with its reason and kept', () async {
    final h = await SyncHarness.create();
    final (checkIn, _) = await recordDay(h);
    h.server.rejectNextWith = 'Attendance already recorded for 2026-10-28';

    final report = await h.sync.sync();
    expect(report.counts.rejected, 1);
    expect(report.counts.synced, 1);
    final events = await h.store.recentEvents();
    final rejected = events.firstWhere((e) => e.id == checkIn.id);
    expect(rejected.status, SyncStatus.rejected);
    expect(rejected.lastError, contains('already recorded'));
  });

  test('a transient failure stops the run so check-out is never sent before check-in', () async {
    final h = await SyncHarness.create();
    final (checkIn, checkOut) = await recordDay(h);
    h.server.failNext = 1;

    final report = await h.sync.sync();
    expect(report.counts.pending, 2);
    expect(h.server.sentEventIds, [checkIn.id], reason: 'check-out was not attempted');

    final retry = await h.sync.sync(manual: true);
    expect(retry.counts.synced, 2);
    expect(h.server.order, ['check_in:${checkIn.id}', 'check_out:${checkOut.id}']);
  });

  test('automatic runs respect backoff but manual Sync Now does not', () async {
    final h = await SyncHarness.create();
    await recordDay(h);
    h.server.failNext = 1;
    await h.sync.sync();

    final auto = await h.sync.sync();
    expect(auto.blockedByFailure, isTrue);
    expect(h.server.sentEventIds, hasLength(1), reason: 'still backing off, nothing sent');

    h.clockHolder.now = h.clockHolder.now.add(const Duration(minutes: 10));
    expect((await h.sync.sync()).counts.synced, 2);
  });

  test('concurrent sync calls share one run and never double-submit', () async {
    final h = await SyncHarness.create();
    await recordDay(h);
    final reports = await Future.wait([h.sync.sync(), h.sync.sync(), h.sync.sync(manual: true)]);
    expect(reports.every((r) => r.counts.synced == 2), isTrue);
    expect(h.server.sentEventIds, hasLength(2));
  });

  test('server 5xx and transport errors never reject an event', () async {
    final h = await SyncHarness.create();
    await recordDay(h);
    h.server.failNext = 3;
    for (var i = 0; i < 3; i++) {
      await h.sync.sync(manual: true);
    }
    final counts = await h.store.counts();
    expect(counts.rejected, 0);
    expect(counts.pending, 2);
  });
}

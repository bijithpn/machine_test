import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rebs_hrms/core/errors/exceptions.dart';
import 'package:rebs_hrms/data/local/cache_store.dart';
import 'package:rebs_hrms/data/local/leave_outbox_store.dart';
import 'package:rebs_hrms/data/remote/hrms_api.dart';
import 'package:rebs_hrms/data/repositories/leave_repository.dart';
import 'package:rebs_hrms/domain/leave_rules.dart';
import 'package:rebs_hrms/domain/models.dart';

import '../support/fakes.dart';

DateTime d(int month, int day) => DateTime.utc(2026, month, day);
final today = d(10, 28);

LeaveRequest request(LeaveStatus status, DateTime s, DateTime e) =>
    LeaveRequest(id: 'x', type: LeaveType.casual, start: s, end: e, reason: 'Some reason', status: status);

Map<String, String> validate(LeaveDraft draft, {int balance = 10, List<LeaveRequest> existing = const []}) =>
    LeaveRules.validate(draft: draft, today: today, balance: balance, existing: existing);

LeaveDraft draft({DateTime? start, DateTime? end, String reason = 'Family function this week'}) =>
    LeaveDraft(type: LeaveType.casual, start: start ?? d(11, 2), end: end ?? d(11, 3), reason: reason);

void main() {
  group('rules', () {
    test('day count is inclusive', () {
      expect(LeaveRules.dayCount(d(11, 2), d(11, 2)), 1);
      expect(LeaveRules.dayCount(d(11, 2), d(11, 4)), 3);
      expect(LeaveRules.dayCount(d(10, 30), d(11, 2)), 4, reason: 'spans a month boundary');
    });

    test('valid request has no errors', () => expect(validate(draft()), isEmpty));

    test('start today is allowed, yesterday is not', () {
      expect(validate(draft(start: today, end: today)), isEmpty);
      expect(validate(draft(start: d(10, 27), end: d(10, 28))), contains('startDate'));
    });

    test(
      'end before start is invalid',
      () => expect(validate(draft(start: d(11, 5), end: d(11, 4))), contains('endDate')),
    );

    test('reason needs 10 non-whitespace characters', () {
      expect(validate(draft(reason: '  short    ')), contains('reason'));
      expect(validate(draft(reason: 'a b c d e f g h i')), contains('reason'));
      expect(validate(draft(reason: 'a b c d e f g h i j')), isEmpty);
    });

    test('days over the balance are rejected; exactly the balance is fine', () {
      expect(validate(draft(start: d(11, 2), end: d(11, 6)), balance: 4), contains('endDate'));
      expect(validate(draft(start: d(11, 2), end: d(11, 5)), balance: 4), isEmpty);
    });

    test('overlap with pending or approved blocks; rejected does not', () {
      final range = draft(start: d(11, 10), end: d(11, 12));
      for (final status in [LeaveStatus.pending, LeaveStatus.approved]) {
        expect(validate(range, existing: [request(status, d(11, 12), d(11, 14))]), contains('startDate'));
        expect(validate(range, existing: [request(status, d(11, 1), d(11, 10))]), contains('startDate'));
        expect(validate(range, existing: [request(status, d(11, 11), d(11, 11))]), contains('startDate'));
      }
      expect(validate(range, existing: [request(LeaveStatus.rejected, d(11, 10), d(11, 12))]), isEmpty);
      expect(validate(range, existing: [request(LeaveStatus.approved, d(11, 13), d(11, 14))]), isEmpty);
    });
  });

  group('repository', () {
    late FakeAdapter adapter;
    late LeaveRepository repo;
    var posts = 0;

    setUp(() async {
      posts = 0;
      adapter = FakeAdapter((o) {
        if (o.method == 'POST') {
          posts++;
          return jsonBody(422, {
            'message': 'Leave request is invalid',
            'errors': {'startDate': 'Leave cannot be taken during the quarterly release freeze'},
          });
        }
        if (o.path == '/leave/balance') return jsonBody(200, {'available': 10});
        return jsonBody(200, {'requests': <Object>[]});
      });
      final db = await openTestDb();
      final api = HrmsApi(Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter);
      repo = LeaveRepository(api, CacheStore(db), LeaveOutboxStore(db), TestClock().clock);
      await repo.refresh();
    });

    test('server-side validation errors are surfaced per field', () async {
      await expectLater(
        repo.submit(draft()),
        throwsA(
          isA<LeaveValidationException>().having((e) => e.fieldErrors['startDate'], 'startDate', contains('freeze')),
        ),
      );
    });

    test('locally invalid drafts never reach the server', () async {
      await expectLater(repo.submit(draft(reason: 'short')), throwsA(isA<LeaveValidationException>()));
      expect(posts, 0);
    });

    test('submitting while offline queues the request, keeps cached data and reserves the days', () async {
      adapter.handler = (o) => throw DioException.connectionError(requestOptions: o, reason: 'down');
      expect(await repo.submit(draft()), LeaveSubmitResult.queued);
      final cached = await repo.cached();
      expect(cached.balance, 10);
      expect(cached.queued, hasLength(1));
      expect(cached.available, 8);
      await expectLater(
        repo.submit(draft()),
        throwsA(isA<LeaveValidationException>()),
        reason: 'overlaps the queued one',
      );
    });

    test('a queued request is sent once with the same request id when the server returns', () async {
      adapter.handler = (o) => throw DioException.connectionError(requestOptions: o, reason: 'down');
      await repo.submit(draft());
      final ids = <String>[];
      adapter.handler = (o) {
        if (o.method == 'POST') {
          ids.add((o.data as Map)['requestId'] as String);
          return jsonBody(201, {
            'id': 'LV-9',
            'type': 'casual',
            'startDate': '2026-11-02',
            'endDate': '2026-11-03',
            'reason': 'Family function this week',
            'status': 'pending',
          });
        }
        return o.path == '/leave/balance' ? jsonBody(200, {'available': 8}) : jsonBody(200, {'requests': <Object>[]});
      };
      final snapshot = await repo.refresh();
      expect(ids, hasLength(1));
      expect(snapshot.queued, isEmpty);
      await repo.refresh();
      expect(ids, hasLength(1), reason: 'nothing left to send');
    });

    test('a queued request refused by the server is kept as rejected with its reason', () async {
      adapter.handler = (o) => throw DioException.connectionError(requestOptions: o, reason: 'down');
      await repo.submit(draft());
      adapter.handler = (o) {
        if (o.method == 'POST') {
          return jsonBody(422, {
            'message': 'Leave request is invalid',
            'errors': {'startDate': 'Leave cannot be taken during the quarterly release freeze'},
          });
        }
        return o.path == '/leave/balance' ? jsonBody(200, {'available': 10}) : jsonBody(200, {'requests': <Object>[]});
      };
      final snapshot = await repo.refresh();
      expect(snapshot.queued.single.status, SyncStatus.rejected);
      expect(snapshot.queued.single.lastError, contains('freeze'));
      expect(snapshot.available, 10, reason: 'rejected requests release the days');
    });

    test('an overlapping second submission while one is in flight is refused', () async {
      adapter.handler = (o) async {
        if (o.method == 'POST') {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          posts++;
          return jsonBody(201, {
            'id': 'LV-1',
            'type': 'casual',
            'startDate': '2026-11-02',
            'endDate': '2026-11-03',
            'reason': 'Family function this week',
            'status': 'pending',
          });
        }
        return o.path == '/leave/balance' ? jsonBody(200, {'available': 8}) : jsonBody(200, {'requests': <Object>[]});
      };
      final results = await Future.wait([
        repo.submit(draft()).then<Object>((r) => r).catchError((Object e) => e),
        repo.submit(draft()).then<Object>((r) => r).catchError((Object e) => e),
      ]);
      expect(posts, 1);
      expect(results.whereType<ApiException>(), hasLength(1));
    });

    test('cached balance and requests are readable when refresh fails', () async {
      adapter.handler = (o) => throw DioException.connectionError(requestOptions: o, reason: 'down');
      await expectLater(repo.refresh(), throwsA(isA<ApiException>()));
      expect((await repo.cached()).hasData, isTrue);
    });
  });
}

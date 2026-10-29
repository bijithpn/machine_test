import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:rebs_hrms/core/time/company_clock.dart';
import 'package:rebs_hrms/data/local/app_database.dart';
import 'package:rebs_hrms/data/local/attendance_store.dart';
import 'package:rebs_hrms/data/location/location_service.dart';
import 'package:rebs_hrms/data/remote/hrms_api.dart';
import 'package:rebs_hrms/data/sync/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const officeLat = 12.9716;
const officeLng = 77.5946;

Future<Database> openTestDb([String? path]) {
  sqfliteFfiInit();
  // inMemoryDatabasePath is a process-wide singleton under ffi, so use a fresh file per call.
  path ??= p.join(Directory.systemTemp.createTempSync('rebs_db').path, 'test.db');
  return AppDatabase.open(path, factory: databaseFactoryFfi);
}

class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 28, 4);
  DateTime now;
  late final CompanyClock clock = CompanyClock(timezone: 'Asia/Kolkata', now: () => now);
}

class FakeLocation implements LocationService {
  FakeLocation({this.lat = officeLat, this.lng = officeLng, this.delay = Duration.zero});
  double lat;
  double lng;
  Duration delay;
  Object? error;
  var calls = 0;

  @override
  Future<LocationFix> currentFix() async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return LocationFix(lat, lng);
  }
}

typedef Handler = FutureOr<ResponseBody> Function(RequestOptions o);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  Handler handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body, Future<void>? cancel) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

DioException timeoutFor(RequestOptions o) =>
    DioException.receiveTimeout(timeout: const Duration(seconds: 6), requestOptions: o);

/// Minimal stand-in for the mock server's attendance event semantics.
class FakeEventServer {
  final processed = <String, ({int code, Map<String, dynamic> body})>{};
  final order = <String>[];
  final sentEventIds = <String>[];
  var dropNextResponseAfterCommit = false;
  var failNext = 0;
  String? rejectNextWith;

  FutureOr<ResponseBody> handle(RequestOptions o) {
    if (o.path != '/attendance/events') return jsonBody(404, {'message': 'nope'});
    final data = o.data as Map<String, dynamic>;
    final id = data['eventId'] as String;
    sentEventIds.add(id);
    if (failNext > 0) {
      failNext--;
      return jsonBody(500, {'message': 'boom'});
    }
    final seen = processed[id];
    if (seen != null) return jsonBody(seen.code, {...seen.body, if (seen.code == 200) 'replayed': true});

    final outcome = rejectNextWith == null
        ? (code: 200, body: <String, dynamic>{'status': 'accepted', 'replayed': false})
        : (code: 409, body: <String, dynamic>{'status': 'rejected', 'message': rejectNextWith});
    rejectNextWith = null;
    processed[id] = outcome;
    if (outcome.code == 200) order.add('${data['type']}:$id');
    if (dropNextResponseAfterCommit) {
      dropNextResponseAfterCommit = false;
      throw timeoutFor(o);
    }
    return jsonBody(outcome.code, outcome.body);
  }
}

class SyncHarness {
  SyncHarness._(this.db, this.clockHolder, this.server, this.adapter);
  final Database db;
  final TestClock clockHolder;
  final FakeEventServer server;
  final FakeAdapter adapter;

  late final store = AttendanceStore(db);
  late final api = HrmsApi(Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter);
  late final sync = SyncService(store, api, clockHolder.clock);

  static Future<SyncHarness> create({Database? db, TestClock? clock}) async {
    final server = FakeEventServer();
    return SyncHarness._(db ?? await openTestDb(), clock ?? TestClock(), server, FakeAdapter(server.handle));
  }
}

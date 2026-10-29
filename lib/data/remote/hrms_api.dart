import 'package:dio/dio.dart';

import '../../core/errors/exceptions.dart';
import '../../domain/models.dart';

sealed class SendResult {
  const SendResult();
}

class EventAccepted extends SendResult {
  const EventAccepted({required this.replayed});
  final bool replayed;
}

class EventRejected extends SendResult {
  const EventRejected(this.reason, {this.code});
  final String reason;
  final String? code;
}

class EventTransientFailure extends SendResult {
  const EventTransientFailure(this.message, {required this.uncertain});
  final String message;
  final bool uncertain;
}

class HrmsApi {
  HrmsApi(this._dio);
  final Dio _dio;

  Future<T> _get<T>(String path, T Function(dynamic) parse, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      return parse(res.data);
    } on DioException catch (e) {
      throw _asException(e);
    }
  }

  ApiException _asException(DioException e) {
    final data = e.response?.data;
    final msg = data is Map && data['message'] is String ? data['message'] as String : null;
    return ApiException(msg ?? _transportMessage(e), statusCode: e.response?.statusCode);
  }

  static bool isConnectivityFailure(Object e) => e is ApiException && e.statusCode == null;

  String _transportMessage(DioException e) => switch (e.type) {
    DioExceptionType.connectionError || DioExceptionType.connectionTimeout => 'Cannot reach the server',
    DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout => 'The server took too long to respond',
    _ => 'Unexpected network error',
  };

  Future<Employee> employee() => _get('/employee/me', (d) => Employee.fromJson(d as Map<String, dynamic>));

  Future<List<({String date, DateTime? checkIn, DateTime? checkOut})>> attendanceMonth(String month) =>
      _get('/attendance', query: {'month': month}, (d) {
        final list = (d as Map<String, dynamic>)['records'] as List;
        return [
          for (final r in list.cast<Map<String, dynamic>>())
            (
              date: r['date'] as String,
              checkIn: r['checkIn'] == null ? null : DateTime.parse(r['checkIn'] as String),
              checkOut: r['checkOut'] == null ? null : DateTime.parse(r['checkOut'] as String),
            ),
        ];
      });

  Future<int> leaveBalance() => _get('/leave/balance', (d) => (d as Map<String, dynamic>)['available'] as int);

  Future<List<LeaveRequest>> leaveRequests() => _get(
    '/leave/requests',
    (d) => [
      for (final r in ((d as Map<String, dynamic>)['requests'] as List).cast<Map<String, dynamic>>())
        LeaveRequest.fromJson(r),
    ],
  );

  Future<LeaveRequest> submitLeave(LeaveDraft draft, {required String requestId}) async {
    try {
      final res = await _dio.post<dynamic>(
        '/leave/requests',
        data: {
          'requestId': requestId,
          'type': draft.type.name,
          'startDate': _date(draft.start!),
          'endDate': _date(draft.end!),
          'reason': draft.reason.trim(),
        },
      );
      return LeaveRequest.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 422 && data is Map) {
        final errors = (data['errors'] as Map?)?.map((k, v) => MapEntry(k as String, v as String)) ?? {};
        throw LeaveValidationException(errors, data['message'] as String?);
      }
      throw _asException(e);
    }
  }

  String _date(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> setMockOffice(double latitude, double longitude) async {
    try {
      await _dio.post<dynamic>('/__mock/office', data: {'latitude': latitude, 'longitude': longitude});
    } on DioException catch (e) {
      throw _asException(e);
    }
  }

  Future<SendResult> sendEvent(AttendanceEvent e) async {
    try {
      final res = await _dio.post<dynamic>(
        '/attendance/events',
        data: {
          'eventId': e.id,
          'employeeId': e.employeeId,
          'type': e.type.wire,
          'timestamp': e.timestamp.toUtc().toIso8601String(),
          'latitude': e.latitude,
          'longitude': e.longitude,
        },
        options: Options(headers: {'Idempotency-Key': e.idempotencyKey}),
      );
      final body = res.data;
      return EventAccepted(replayed: body is Map && body['replayed'] == true);
    } on DioException catch (err) {
      return _classify(err);
    }
  }

  SendResult _classify(DioException e) {
    final code = e.response?.statusCode;
    if (code == null) {
      final sent = e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout;
      return EventTransientFailure(_transportMessage(e), uncertain: sent);
    }
    final data = e.response?.data;
    final reason = data is Map && data['message'] is String ? data['message'] as String : 'Rejected by server ($code)';
    // Auth problems and throttling heal on their own; other 4xx are final.
    const retryable = {401, 403, 408, 425, 429};
    if (code >= 500 || retryable.contains(code)) {
      return EventTransientFailure('Server error ($code)', uncertain: false);
    }
    return EventRejected(reason, code: data is Map ? data['code'] as String? : null);
  }
}

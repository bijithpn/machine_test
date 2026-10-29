// ignore_for_file: avoid_print
// Manual end-to-end check of HrmsApi against a running mock server:
//   dart run tool/e2e_check.dart http://localhost:3000
import 'package:dio/dio.dart';
import 'package:rebs_hrms/data/remote/hrms_api.dart';
import 'package:rebs_hrms/domain/models.dart';

Future<void> main(List<String> args) async {
  final base = args.isEmpty ? 'http://localhost:3000' : args.first;
  final dio = Dio(BaseOptions(baseUrl: base, receiveTimeout: const Duration(seconds: 2)));
  final api = HrmsApi(dio);
  print('employee: ${(await api.employee()).name}');
  print('balance: ${await api.leaveBalance()}');
  print('requests: ${(await api.leaveRequests()).length}');

  final event = AttendanceEvent(
    id: 'e2e-${DateTime.now().millisecondsSinceEpoch}',
    employeeId: 'EMP-1042',
    type: AttendanceType.checkIn,
    timestamp: DateTime.now().toUtc(),
    workDate: '',
    latitude: 12.9716,
    longitude: 77.5946,
  );
  await dio.post<void>('/__mock/scenario', data: {'name': 'timeout_after_accept', 'delayMs': 3000});
  final first = await api.sendEvent(event);
  print(
    'first send (response delayed past timeout): ${first.runtimeType} uncertain=${first is EventTransientFailure && first.uncertain}',
  );
  final retry = await api.sendEvent(event);
  print('retry same id: ${retry.runtimeType} replayed=${retry is EventAccepted && retry.replayed}');
  final dup = await api.sendEvent(
    AttendanceEvent(
      id: '${event.id}-2',
      employeeId: 'EMP-1042',
      type: AttendanceType.checkIn,
      timestamp: DateTime.now().toUtc(),
      workDate: '',
      latitude: 12.9716,
      longitude: 77.5946,
    ),
  );
  print('second check-in new id: ${dup is EventRejected ? 'Rejected: ${dup.reason}' : dup.runtimeType}');
}

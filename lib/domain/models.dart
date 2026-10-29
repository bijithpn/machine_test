import '../core/time/company_clock.dart';

enum AttendanceType {
  checkIn('check_in'),
  checkOut('check_out');

  const AttendanceType(this.wire);
  final String wire;
  static AttendanceType fromWire(String s) => values.firstWhere((t) => t.wire == s);
}

enum SyncStatus { pending, synced, rejected }

enum AttendanceStatus { notCheckedIn, checkedIn, checkedOut }

class Employee {
  const Employee({required this.id, required this.name, required this.department});
  final String id;
  final String name;
  final String department;

  factory Employee.fromJson(Map<String, dynamic> j) =>
      Employee(id: j['id'] as String, name: j['name'] as String, department: j['department'] as String);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'department': department};
}

class AttendanceEvent {
  const AttendanceEvent({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.timestamp,
    required this.workDate,
    required this.latitude,
    required this.longitude,
    this.status = SyncStatus.pending,
    this.attempts = 0,
    this.lastError,
    this.uncertain = false,
    this.nextAttemptAt,
  });

  final String id;
  final String employeeId;
  final AttendanceType type;
  final DateTime timestamp;
  final String workDate;
  final double latitude;
  final double longitude;
  final SyncStatus status;
  final int attempts;
  final String? lastError;

  final bool uncertain;
  final DateTime? nextAttemptAt;

  String get idempotencyKey => id;
}

class AttendanceDay {
  const AttendanceDay({
    required this.date,
    this.checkIn,
    this.checkOut,
    this.sync = SyncStatus.synced,
    this.rejectionReason,
  });

  final String date;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final SyncStatus sync;
  final String? rejectionReason;

  AttendanceStatus get status => checkIn == null
      ? AttendanceStatus.notCheckedIn
      : checkOut == null
      ? AttendanceStatus.checkedIn
      : AttendanceStatus.checkedOut;

  Duration? get worked => checkIn == null || checkOut == null ? null : checkOut!.difference(checkIn!);
}

class SyncCounts {
  const SyncCounts({this.pending = 0, this.synced = 0, this.rejected = 0});
  final int pending;
  final int synced;
  final int rejected;
}

enum LeaveType { casual, sick }

enum LeaveStatus { pending, approved, rejected }

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    required this.reason,
    required this.status,
  });

  final String id;
  final LeaveType type;
  final DateTime start;
  final DateTime end;
  final String reason;
  final LeaveStatus status;

  int get days => end.difference(start).inDays + 1;

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
    id: j['id'] as String,
    type: LeaveType.values.byName(j['type'] as String),
    start: CompanyClock.parseDate(j['startDate'] as String),
    end: CompanyClock.parseDate(j['endDate'] as String),
    reason: j['reason'] as String,
    status: LeaveStatus.values.byName(j['status'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'startDate': CompanyClock.formatDate(start),
    'endDate': CompanyClock.formatDate(end),
    'reason': reason,
    'status': status.name,
  };
}

class LeaveDraft {
  const LeaveDraft({required this.type, this.start, this.end, required this.reason});
  final LeaveType type;
  final DateTime? start;
  final DateTime? end;
  final String reason;
}

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

class Office {
  const Office({required this.latitude, required this.longitude, required this.radiusMeters});
  final double latitude;
  final double longitude;
  final double radiusMeters;

  factory Office.fromJson(Map<String, dynamic> j) => Office(
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    radiusMeters: (j['radiusMeters'] as num).toDouble(),
  );
  Map<String, dynamic> toJson() => {'latitude': latitude, 'longitude': longitude, 'radiusMeters': radiusMeters};
}

class Employee {
  const Employee({required this.id, required this.name, required this.department, this.office});
  final String id;
  final String name;
  final String department;
  final Office? office;

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
    id: j['id'] as String,
    name: j['name'] as String,
    department: j['department'] as String,
    office: j['office'] == null ? null : Office.fromJson(j['office'] as Map<String, dynamic>),
  );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'department': department, 'office': office?.toJson()};
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
    this.rejectCode,
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
  final String? rejectCode;

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

class QueuedLeave {
  const QueuedLeave({
    required this.id,
    required this.draft,
    required this.status,
    required this.createdAt,
    this.lastError,
  });
  final String id;
  final LeaveDraft draft;
  final SyncStatus status;
  final DateTime createdAt;
  final String? lastError;

  int get days => draft.end!.difference(draft.start!).inDays + 1;

  LeaveRequest asRequest() => LeaveRequest(
    id: id,
    type: draft.type,
    start: draft.start!,
    end: draft.end!,
    reason: draft.reason,
    status: LeaveStatus.pending,
  );
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

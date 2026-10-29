import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../errors/exceptions.dart';
import 'tokens.dart';

import 'package:flutter/painting.dart';

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return h == 0 ? '${m}m' : '${h}h ${m.toString().padLeft(2, '0')}m';
}

String formatClockDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

String formatDay(String yyyyMmDd) => DateFormat('EEE, d MMM').format(DateTime.parse(yyyyMmDd));
String formatLongDay(String yyyyMmDd) => DateFormat('EEEE, d MMMM y').format(DateTime.parse(yyyyMmDd));
String formatDateOnly(DateTime d) => DateFormat('d MMM y').format(d);

final _legacyGeofence = RegExp(r'Recorded location was (\d+(?:\.\d+)?) m from the office \(limit (\d+(?:\.\d+)?) m\)');
final _isoDate = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
final _metres = RegExp(r'\b(\d{4,})(?:\.\d+)? m\b');

String formatServerMessage(String message) => message
    .replaceAllMapped(
      _legacyGeofence,
      (m) =>
          'Outside the office area: you were ${formatDistance(double.parse(m[1]!))} from the office. '
          'Attendance must be within ${formatDistance(double.parse(m[2]!))}.',
    )
    .replaceAllMapped(_isoDate, (m) => formatDateOnly(DateTime.parse(m[0]!)))
    .replaceAllMapped(_metres, (m) => formatDistance(double.parse(m[1]!)));

String syncLabel(SyncStatus s) => switch (s) {
  SyncStatus.pending => 'Pending Sync',
  SyncStatus.synced => 'Synced',
  SyncStatus.rejected => 'Rejected',
};

Color syncColor(SyncStatus s) => switch (s) {
  SyncStatus.pending => AppColors.warning,
  SyncStatus.synced => AppColors.success,
  SyncStatus.rejected => AppColors.danger,
};

String attendanceLabel(AttendanceStatus s) => switch (s) {
  AttendanceStatus.notCheckedIn => 'Not Checked In',
  AttendanceStatus.checkedIn => 'Checked In',
  AttendanceStatus.checkedOut => 'Checked Out',
};

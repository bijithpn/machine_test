import 'dart:math' as math;

import '../core/errors/exceptions.dart';
import 'models.dart';

class AttendanceRules {
  static void ensureAllowed(AttendanceType type, AttendanceDay? today) {
    final status = today?.status ?? AttendanceStatus.notCheckedIn;
    switch (type) {
      case AttendanceType.checkIn:
        if (status != AttendanceStatus.notCheckedIn) {
          throw const AttendanceRuleException('You have already checked in today.');
        }
      case AttendanceType.checkOut:
        if (status == AttendanceStatus.notCheckedIn) {
          throw const AttendanceRuleException('You need to check in before checking out.');
        }
        if (status == AttendanceStatus.checkedOut) {
          throw const AttendanceRuleException('You have already checked out today.');
        }
    }
  }

  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final a =
        math.pow(math.sin(rad(lat2 - lat1) / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lon2 - lon1) / 2), 2);
    return 2 * earthRadius * math.asin(math.sqrt(a));
  }
}

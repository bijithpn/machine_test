enum LocationFailure { servicesDisabled, denied, deniedForever, unavailable, timeout }

class LocationException implements Exception {
  const LocationException(this.failure, this.message);
  final LocationFailure failure;
  final String message;
  @override
  String toString() => message;
}

String formatDistance(double meters) =>
    meters.round() < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';

class OutsideOfficeException implements Exception {
  const OutsideOfficeException(this.distanceMeters, this.limitMeters);
  final double distanceMeters;
  final double limitMeters;
  String get message =>
      'You are ${formatDistance(distanceMeters)} from the office. Attendance is only allowed within ${formatDistance(limitMeters)}.';
  @override
  String toString() => message;
}

class AttendanceRuleException implements Exception {
  const AttendanceRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LeaveValidationException implements Exception {
  const LeaveValidationException(this.fieldErrors, [this.message]);
  final Map<String, String> fieldErrors;
  final String? message;
  @override
  String toString() => message ?? fieldErrors.values.join('\n');
}

class OfflineException implements Exception {
  const OfflineException([this.message = 'No connection to the server. Try again when you are back online.']);
  final String message;
  @override
  String toString() => message;
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

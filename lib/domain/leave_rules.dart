import 'models.dart';

class LeaveRules {
  static const minReasonChars = 10;

  static int dayCount(DateTime start, DateTime end) => end.difference(start).inDays + 1;

  static Map<String, String> validate({
    required LeaveDraft draft,
    required DateTime today,
    required int balance,
    required List<LeaveRequest> existing,
  }) {
    final errors = <String, String>{};
    final start = draft.start;
    final end = draft.end;

    if (start == null) {
      errors['startDate'] = 'Choose a start date';
    } else if (start.isBefore(today)) {
      errors['startDate'] = 'Start date cannot be before today';
    }
    if (end == null) {
      errors['endDate'] = 'Choose an end date';
    } else if (start != null && end.isBefore(start)) {
      errors['endDate'] = 'End date cannot be before the start date';
    }
    if (draft.reason.replaceAll(RegExp(r'\s'), '').length < minReasonChars) {
      errors['reason'] = 'Reason needs at least $minReasonChars characters';
    }

    if (start != null && end != null && !end.isBefore(start)) {
      final days = dayCount(start, end);
      if (days > balance) {
        errors['endDate'] = 'You requested $days days but only $balance are available';
      }
      final clash = existing.where(
        (r) => r.status != LeaveStatus.rejected && !start.isAfter(r.end) && !end.isBefore(r.start),
      );
      if (clash.isNotEmpty && !errors.containsKey('startDate')) {
        errors['startDate'] = 'Overlaps an existing ${clash.first.status.name} request';
      }
    }
    return errors;
  }
}

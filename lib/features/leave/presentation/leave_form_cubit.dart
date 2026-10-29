import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../../core/time/company_clock.dart';
import '../../../domain/models.dart';

/// Keeps the unsent leave draft across screen exits and app restarts.
class LeaveFormCubit extends HydratedCubit<LeaveDraft> {
  LeaveFormCubit() : super(const LeaveDraft(type: LeaveType.casual, reason: ''));

  void save(LeaveDraft draft) => emit(draft);

  void reset() => emit(const LeaveDraft(type: LeaveType.casual, reason: ''));

  @override
  LeaveDraft? fromJson(Map<String, dynamic> json) => LeaveDraft(
    type: LeaveType.values.byName(json['type'] as String),
    start: json['start'] == null ? null : CompanyClock.parseDate(json['start'] as String),
    end: json['end'] == null ? null : CompanyClock.parseDate(json['end'] as String),
    reason: json['reason'] as String,
  );

  @override
  Map<String, dynamic> toJson(LeaveDraft s) => {
    'type': s.type.name,
    'start': s.start == null ? null : CompanyClock.formatDate(s.start!),
    'end': s.end == null ? null : CompanyClock.formatDate(s.end!),
    'reason': s.reason,
  };
}

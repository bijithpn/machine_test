import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/exceptions.dart';
import '../../../data/repositories/attendance_service.dart';
import '../../../domain/models.dart';
import '../../dashboard/presentation/dashboard_cubit.dart';

class ActionState {
  const ActionState({this.busy = false, this.error, this.locationFailure, this.done});
  final bool busy;
  final AttendanceType? done;
  final String? error;
  final LocationFailure? locationFailure;
}

class AttendanceActionCubit extends Cubit<ActionState> {
  AttendanceActionCubit(this._service, this._dashboard) : super(const ActionState());
  final AttendanceService _service;
  final DashboardCubit _dashboard;

  Future<void> submit(AttendanceType type) async {
    if (state.busy) return;
    emit(const ActionState(busy: true));
    try {
      await _service.record(type);
      emit(ActionState(done: type));
    } on LocationException catch (e) {
      emit(ActionState(error: e.message, locationFailure: e.failure));
    } on OutsideOfficeException catch (e) {
      emit(ActionState(error: e.message));
    } on AttendanceRuleException catch (e) {
      emit(ActionState(error: e.message));
    } catch (_) {
      emit(const ActionState(error: 'Could not save your attendance. Please try again.'));
    }
    if (!isClosed) _dashboard.afterLocalChange();
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/formatters.dart';
import '../../../core/errors/exceptions.dart';
import '../../../data/remote/hrms_api.dart';
import '../../../data/repositories/leave_repository.dart';
import '../../../domain/models.dart';

class LeaveState {
  const LeaveState({this.data = const LeaveSnapshot(), this.refreshing = true, this.error, this.offline = false});
  final LeaveSnapshot data;
  final bool refreshing;
  final String? error;
  final bool offline;
}

class LeaveCubit extends Cubit<LeaveState> {
  LeaveCubit(this._repo) : super(const LeaveState()) {
    _start();
  }

  final LeaveRepository _repo;

  Future<void> _start() async {
    final cached = await _repo.cached();
    if (isClosed) return;
    emit(LeaveState(data: cached));
    await refresh();
  }

  Future<void> refresh() async {
    emit(LeaveState(data: state.data));
    try {
      final fresh = await _repo.refresh();
      if (!isClosed) emit(LeaveState(data: fresh, refreshing: false));
    } on ApiException catch (e) {
      final cached = await _repo.cached();
      if (!isClosed) {
        emit(
          LeaveState(
            data: cached,
            refreshing: false,
            error: formatServerMessage(e.message),
            offline: HrmsApi.isConnectivityFailure(e),
          ),
        );
      }
    }
  }

  Future<LeaveSubmitResult> submit(LeaveDraft draft) async {
    final result = await _repo.submit(draft);
    final cached = await _repo.cached();
    if (!isClosed) emit(LeaveState(data: cached, refreshing: false, error: state.error, offline: state.offline));
    return result;
  }

  Future<void> dismiss(String id) async {
    await _repo.dismiss(id);
    final cached = await _repo.cached();
    if (!isClosed) emit(LeaveState(data: cached, refreshing: false, error: state.error, offline: state.offline));
  }

  Future<void> backgroundSync() async {
    if (state.refreshing) return;
    if (state.offline || state.error != null || state.data.pendingQueued > 0) await refresh();
  }
}

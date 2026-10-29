import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/exceptions.dart';
import '../../../data/remote/hrms_api.dart';
import '../../../data/repositories/workspace_repository.dart';
import '../../../data/sync/sync_service.dart';

class DashboardState {
  const DashboardState({
    this.data = const WorkspaceSnapshot(),
    this.refreshing = true,
    this.error,
    this.offline = false,
  });
  final WorkspaceSnapshot data;
  final bool refreshing;
  final String? error;
  final bool offline;
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repo, this._sync) : super(const DashboardState()) {
    _start();
  }

  final WorkspaceRepository _repo;
  final SyncService _sync;
  var _refreshes = 0;

  Future<void> _start() async {
    final data = await _repo.local();
    if (isClosed) return;
    emit(DashboardState(data: data));
    await refresh();
  }

  Future<void> refresh({bool manualSync = false}) async {
    _refreshes++;
    emit(DashboardState(data: state.data, refreshing: true));
    String? error;
    var offline = false;
    try {
      await _sync.sync(manual: manualSync);
      await _repo.refresh();
    } on ApiException catch (e) {
      error = e.message;
      offline = HrmsApi.isConnectivityFailure(e);
    } finally {
      _refreshes--;
    }
    await _publish(error: error, offline: offline);
  }

  Future<void> _publish({String? error, bool offline = false}) async {
    final data = await _repo.local();
    if (isClosed) return;
    emit(DashboardState(data: data, refreshing: _refreshes > 0, error: error, offline: offline));
  }

  Future<void> afterLocalChange() async {
    final data = await _repo.local();
    if (isClosed) return;
    emit(DashboardState(data: data, refreshing: state.refreshing, error: state.error, offline: state.offline));
    unawaited(refresh());
  }

  Future<SyncReport> syncNow() async {
    final report = await _sync.sync(manual: true);
    await refresh();
    return report;
  }

  Future<void> backgroundSync() async {
    if (state.data.counts.pending == 0) return;
    final report = await _sync.sync();
    if (report.sent > 0) {
      await refresh();
    } else {
      await _publish(error: state.error, offline: state.offline);
    }
  }
}

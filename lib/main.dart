import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/time/company_clock.dart';
import 'data/local/app_database.dart';
import 'data/local/attendance_store.dart';
import 'data/local/cache_store.dart';
import 'data/local/leave_outbox_store.dart';
import 'data/location/location_override_cubit.dart';
import 'data/location/location_service.dart';
import 'data/remote/hrms_api.dart';
import 'data/repositories/attendance_service.dart';
import 'data/repositories/leave_repository.dart';
import 'data/repositories/workspace_repository.dart';
import 'data/sync/sync_service.dart';
import 'features/attendance/presentation/attendance_cubit.dart';
import 'features/dashboard/presentation/connectivity_cubit.dart';
import 'features/dashboard/presentation/dashboard_cubit.dart';
import 'features/leave/presentation/leave_cubit.dart';
import 'features/leave/presentation/leave_form_cubit.dart';

bool _online(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: HydratedStorageDirectory((await getApplicationSupportDirectory()).path),
  );
  final db = await AppDatabase.open(p.join(await getDatabasesPath(), 'rebs_hrms.db'));
  final clock = CompanyClock(timezone: AppConfig.companyTimezone);
  final api = HrmsApi(
    Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 6),
        headers: {'Accept': 'application/json'},
      ),
    ),
  );
  final cache = CacheStore(db);
  final attendance = AttendanceStore(db);
  final sync = SyncService(attendance, api, clock);
  final workspace = WorkspaceRepository(api, cache, attendance, clock);
  final connectivity = Connectivity();
  final startOnline = _online(await connectivity.checkConnectivity());

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: api),
        RepositoryProvider.value(value: clock),
        BlocProvider(create: (_) => LocationOverrideCubit()),
        RepositoryProvider(
          create: (c) => AttendanceService(
            attendance,
            kDebugMode
                ? OverridableLocationService(createLocationService(), c.read<LocationOverrideCubit>())
                : createLocationService(),
            clock,
            employeeId: AppConfig.employeeId,
            officeLatitude: AppConfig.officeLatitude,
            officeLongitude: AppConfig.officeLongitude,
            serverOffice: workspace.cachedOffice,
            officeOverride: kDebugMode ? () => c.read<LocationOverrideCubit>().state.office : null,
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ConnectivityCubit(connectivity.onConnectivityChanged.map(_online), initial: startOnline),
          ),
          BlocProvider(create: (_) => DashboardCubit(workspace, sync)),
          BlocProvider(create: (c) => AttendanceActionCubit(c.read<AttendanceService>(), c.read<DashboardCubit>())),
          BlocProvider(create: (_) => LeaveFormCubit()),
          BlocProvider(create: (_) => LeaveCubit(LeaveRepository(api, cache, LeaveOutboxStore(db), clock))),
        ],
        child: const RebsApp(),
      ),
    ),
  );
}

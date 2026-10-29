import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rebs_hrms/data/location/location_override_cubit.dart';
import 'package:rebs_hrms/core/time/company_clock.dart';
import 'package:rebs_hrms/core/design/theme.dart';
import 'package:rebs_hrms/data/repositories/workspace_repository.dart';
import 'package:rebs_hrms/domain/models.dart';

import '../support/fakes.dart';

import 'package:rebs_hrms/features/dashboard/presentation/dashboard_cubit.dart';
import 'package:rebs_hrms/features/attendance/presentation/attendance_cubit.dart';
import 'package:rebs_hrms/features/dashboard/presentation/connectivity_cubit.dart';
import 'package:rebs_hrms/features/dashboard/presentation/dashboard_screen.dart';

class FakeDashboardCubit extends Cubit<DashboardState> implements DashboardCubit {
  FakeDashboardCubit(super.state);
  var refreshCalls = 0;

  @override
  Future<void> refresh({bool manualSync = false}) async => refreshCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeActionCubit extends Cubit<ActionState> implements AttendanceActionCubit {
  FakeActionCubit() : super(const ActionState());

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const employee = Employee(id: 'EMP-1042', name: 'Priya Nair', department: 'Product Engineering');

Future<FakeDashboardCubit> pump(WidgetTester tester, DashboardState state, {bool online = true}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  HydratedBloc.storage = MemoryStorage();
  final cubit = FakeDashboardCubit(state);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<DashboardCubit>.value(value: cubit),
        BlocProvider<AttendanceActionCubit>(create: (_) => FakeActionCubit()),
        BlocProvider(create: (_) => LocationOverrideCubit()),
        BlocProvider(create: (_) => ConnectivityCubit(const Stream.empty(), initial: online)),
      ],
      child: RepositoryProvider(
        create: (_) => CompanyClock(timezone: 'Asia/Kolkata'),
        child: MaterialApp(theme: buildTheme(), home: const DashboardScreen()),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

void main() {
  testWidgets('offline with pending and rejected actions shows saved data and sync states', (tester) async {
    final checkIn = DateTime.now().toUtc().subtract(const Duration(hours: 2));
    final today = AttendanceDay(date: '2026-10-28', checkIn: checkIn, sync: SyncStatus.pending);
    await pump(
      tester,
      DashboardState(
        refreshing: false,
        offline: true,
        error: 'Cannot reach the server',
        data: WorkspaceSnapshot(
          employee: employee,
          balance: 12,
          today: today,
          days: [
            today,
            const AttendanceDay(
              date: '2026-10-27',
              sync: SyncStatus.rejected,
              rejectionReason: 'Attendance already recorded',
            ),
          ],
          counts: const SyncCounts(pending: 2, rejected: 1, synced: 4),
        ),
      ),
      online: false,
    );

    expect(find.text('Priya Nair'), findsOneWidget);
    expect(find.textContaining('Offline. Showing saved data'), findsOneWidget);
    expect(find.text('2 attendance actions waiting to sync.'), findsOneWidget);
    expect(find.textContaining('1 action was rejected'), findsOneWidget);
    expect(find.text('Checked In'), findsOneWidget);
    expect(find.text('Pending Sync'), findsWidgets);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Attendance already recorded'), findsOneWidget);
    expect(find.text('Check out'), findsOneWidget);
    expect(find.text('12 days'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull, reason: 'elapsed timer is cancelled on dispose');
  });

  testWidgets('first launch with no cache and no network shows an offline error with retry', (tester) async {
    final fake = await pump(
      tester,
      const DashboardState(
        refreshing: false,
        offline: true,
        error: 'Cannot reach the server',
        data: WorkspaceSnapshot(),
      ),
      online: false,
    );
    expect(find.text('You are offline'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(fake.refreshCalls, 1);
  });

  testWidgets('empty history and not-checked-in state', (tester) async {
    await pump(
      tester,
      const DashboardState(refreshing: false, data: WorkspaceSnapshot(employee: employee, balance: 1)),
    );
    expect(find.text('Not Checked In'), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('No attendance records yet.'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
  });
}

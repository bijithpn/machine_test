import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/design/theme.dart';
import '../features/attendance/presentation/attendance_screen.dart';
import '../features/dashboard/presentation/connectivity_cubit.dart';
import '../features/dashboard/presentation/dashboard_cubit.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/leave/presentation/leave_screen.dart';

class RebsApp extends StatelessWidget {
  const RebsApp({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(title: 'REBS HRMS', debugShowCheckedModeBanner: false, theme: buildTheme(), home: const HomeShell());
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  var _index = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Picks up events whose backoff has elapsed while the app stays open.
    _retryTimer = Timer.periodic(const Duration(seconds: 20), (_) => context.read<DashboardCubit>().backgroundSync());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<DashboardCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ConnectivityCubit, bool>(
      listenWhen: (prev, next) => !prev && next,
      listener: (context, _) => context.read<DashboardCubit>().refresh(manualSync: true),
      child: Scaffold(
        body: IndexedStack(index: _index, children: const [DashboardScreen(), AttendanceScreen(), LeaveScreen()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
              icon: Icon(Icons.access_time),
              selectedIcon: Icon(Icons.access_time_filled),
              label: 'Attendance',
            ),
            NavigationDestination(
              icon: Icon(Icons.beach_access_outlined),
              selectedIcon: Icon(Icons.beach_access),
              label: 'Leave',
            ),
          ],
        ),
      ),
    );
  }
}

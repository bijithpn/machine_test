import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/config/app_config.dart';
import '../../../core/time/company_clock.dart';
import '../../../core/design/feedback.dart';
import '../../../core/design/formatters.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets.dart';
import '../../../core/errors/exceptions.dart';
import '../../../domain/models.dart';
import '../../attendance/presentation/attendance_cubit.dart';
import '../../../data/location/location_override_cubit.dart';
import 'clear_rejected.dart';
import 'connectivity_cubit.dart';
import 'dashboard_cubit.dart';
import 'elapsed_text.dart';
import 'location_override_sheet.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DashboardCubit>().state;
    final online = context.watch<ConnectivityCubit>().state;
    final employee = state.data.employee;

    return Scaffold(
      appBar: AppBar(
        title: const Text('REBS HRMS'),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'Test location',
              icon: Icon(
                !context.watch<LocationOverrideCubit>().state.isActive ? Icons.location_searching : Icons.my_location,
              ),
              onPressed: () => showLocationOverride(context),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<DashboardCubit>().refresh(manualSync: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Header(employee: employee),
            const SizedBox(height: AppSpacing.md),
            DashboardBanners(state: state, online: online),
            _TodayCard(state: state),
            const SizedBox(height: AppSpacing.md),
            _BalanceCard(balance: state.data.balance),
            const SizedBox(height: AppSpacing.lg),
            const SectionTitle('Recent attendance'),
            _RecentList(days: state.data.recent),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.employee});
  final Employee? employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(employee?.name ?? 'Welcome', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          employee == null ? AppConfig.employeeId : '${employee!.id} · ${employee!.department}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        Text(formatLongDay(context.read<CompanyClock>().today), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class DashboardBanners extends StatelessWidget {
  const DashboardBanners({super.key, required this.state, required this.online});
  final DashboardState state;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final counts = state.data.counts;
    final offline = state.offline || !online;
    final banners = <Widget>[
      if (offline)
        const StatusBanner(
          tone: BannerTone.warning,
          icon: Icons.cloud_off_outlined,
          message: 'Offline. Showing saved data; new attendance is stored on this device and will sync automatically when you are back online.',
        )
      else if (state.error != null)
        StatusBanner(
          tone: BannerTone.warning,
          icon: Icons.sync_problem_outlined,
          message: '${state.error}. Showing saved data.',
          action: TextButton(
            onPressed: () => context.read<DashboardCubit>().refresh(manualSync: true),
            child: const Text('Retry'),
          ),
        ),
      if (counts.pending > 0)
        StatusBanner(
          tone: BannerTone.info,
          icon: Icons.schedule,
          message: '${counts.pending} attendance ${counts.pending == 1 ? 'action' : 'actions'} waiting to sync.',
          action: TextButton(
            onPressed: state.refreshing ? null : () => context.read<DashboardCubit>().syncNow(),
            child: const Text('Sync now'),
          ),
        ),
      if (counts.rejected > 0)
        StatusBanner(
          tone: BannerTone.danger,
          icon: Icons.error_outline,
          message:
              '${counts.rejected} ${counts.rejected == 1 ? 'action was' : 'actions were'} rejected by the server. See the Attendance tab.',
          action: TextButton(onPressed: () => confirmClearRejected(context), child: const Text('Dismiss')),
        ),
    ];
    if (state.refreshing) banners.insert(0, const LinearProgressIndicator(minHeight: 2));
    return Column(
      children: [
        for (final b in banners)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: b,
          ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.state});
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = context.read<CompanyClock>();
    final today = state.data.today;
    final status = today?.status ?? AttendanceStatus.notCheckedIn;
    final action = context.watch<AttendanceActionCubit>().state;

    String time(DateTime? t) => t == null ? '--' : clock.formatTime(t);

    final Widget duration = switch (status) {
      AttendanceStatus.checkedIn => ElapsedText(since: today!.checkIn!),
      AttendanceStatus.checkedOut => Text(formatDuration(today!.worked!), style: theme.textTheme.titleLarge),
      AttendanceStatus.notCheckedIn => Text('--', style: theme.textTheme.titleLarge),
    };

    return BlocListener<AttendanceActionCubit, ActionState>(
      listenWhen: (_, s) => s.done != null || s.error != null,
      listener: _onActionResult,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Today', style: theme.textTheme.titleMedium)),
                if (today != null && today.sync != SyncStatus.synced) ...[
                  StatusChip(syncLabel(today.sync), syncColor(today.sync)),
                  const SizedBox(width: AppSpacing.sm),
                ],
                StatusChip(attendanceLabel(status), switch (status) {
                  AttendanceStatus.notCheckedIn => AppColors.textMuted,
                  AttendanceStatus.checkedIn => AppColors.accent,
                  AttendanceStatus.checkedOut => AppColors.success,
                }),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _Metric(label: 'Check-in', value: time(today?.checkIn)),
                _Metric(label: 'Check-out', value: time(today?.checkOut)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              status == AttendanceStatus.checkedOut ? 'TOTAL WORKED' : 'ELAPSED',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 2),
            duration,
            const SizedBox(height: AppSpacing.md),
            if (status != AttendanceStatus.checkedOut)
              FilledButton(
                onPressed: action.busy
                    ? null
                    : () => _confirm(
                        context,
                        status == AttendanceStatus.notCheckedIn ? AttendanceType.checkIn : AttendanceType.checkOut,
                      ),
                child: action.busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(status == AttendanceStatus.notCheckedIn ? 'Check in' : 'Check out'),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirm(BuildContext context, AttendanceType type) async {
  final cubit = context.read<AttendanceActionCubit>();
  final checkIn = type == AttendanceType.checkIn;
  final ok = await confirmDialog(
    context,
    title: checkIn ? 'Check in?' : 'Check out?',
    message:
        'Your location will be verified against the office before the ${checkIn ? 'check-in' : 'check-out'} is saved.',
    confirmLabel: checkIn ? 'Check in' : 'Check out',
  );
  if (ok) cubit.submit(type);
}

void _onActionResult(BuildContext context, ActionState s) {
  if (s.done != null) {
    showToast(
      context,
      s.done == AttendanceType.checkIn ? 'Checked in. Saved on this device.' : 'Checked out. Saved on this device.',
      kind: ToastKind.success,
    );
  } else if (s.error != null) {
    final (label, open) = switch (s.locationFailure) {
      LocationFailure.deniedForever => ('Open app settings', Geolocator.openAppSettings),
      LocationFailure.servicesDisabled => ('Open location settings', Geolocator.openLocationSettings),
      _ => (null, null),
    };
    errorDialog(
      context,
      title: 'Attendance not saved',
      message: s.error!,
      actionLabel: label,
      onAction: open == null ? null : () => open(),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});
  final int? balance;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Expanded(child: Text('Leave balance', style: Theme.of(context).textTheme.titleMedium)),
        Text(
          balance == null ? '--' : '$balance ${balance == 1 ? 'day' : 'days'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.days});
  final List<AttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty)
      return const AppCard(
        child: EmptyState(message: 'No attendance records yet.', icon: Icons.event_busy_outlined),
      );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < days.length; i++) ...[if (i > 0) const Divider(), AttendanceDayTile(day: days[i])],
        ],
      ),
    );
  }
}

class AttendanceDayTile extends StatelessWidget {
  const AttendanceDayTile({super.key, required this.day});
  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = context.read<CompanyClock>();
    final range =
        '${day.checkIn == null ? '--' : clock.formatTime(day.checkIn!)} – ${day.checkOut == null ? '--' : clock.formatTime(day.checkOut!)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatDay(day.date), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(range, style: theme.textTheme.bodySmall),
                if (day.rejectionReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      formatServerMessage(day.rejectionReason!),
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
                    ),
                  ),
              ],
            ),
          ),
          if (day.sync != SyncStatus.synced)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: StatusChip(syncLabel(day.sync), syncColor(day.sync)),
            ),
          Text(day.worked == null ? '' : formatDuration(day.worked!), style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

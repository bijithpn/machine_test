import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/time/company_clock.dart';
import '../../../core/design/feedback.dart';
import '../../../core/design/formatters.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets.dart';
import '../../../domain/models.dart';
import '../../dashboard/presentation/clear_rejected.dart';
import '../../dashboard/presentation/dashboard_cubit.dart';
import '../../dashboard/presentation/dashboard_screen.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardCubit>().state;
    final data = dashboard.data;

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: RefreshIndicator(
        onRefresh: () => context.read<DashboardCubit>().refresh(manualSync: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _SyncSummary(counts: data.counts, syncing: dashboard.refreshing),
            const SizedBox(height: AppSpacing.lg),

            const SectionTitle('Device events'),
            if (data.events.isEmpty)
              const AppCard(child: EmptyState(message: 'Check-ins and check-outs from this device appear here.'))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < data.events.length; i++) ...[
                      if (i > 0) const Divider(),
                      _EventTile(event: data.events[i]),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            const SectionTitle('History'),
            if (data.days.isEmpty)
              const AppCard(
                child: EmptyState(message: 'No attendance records yet.', icon: Icons.event_busy_outlined),
              )
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < data.days.length; i++) ...[
                      if (i > 0) const Divider(),
                      AttendanceDayTile(day: data.days[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SyncSummary extends StatelessWidget {
  const _SyncSummary({required this.counts, required this.syncing});
  final SyncCounts counts;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String label, int n, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$n', style: theme.textTheme.titleLarge?.copyWith(color: color)),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sync', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              stat('Synced', counts.synced, AppColors.success),
              stat('Pending', counts.pending, AppColors.warning),
              stat('Rejected', counts.rejected, AppColors.danger),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: syncing ? null : () => _syncNow(context),
            icon: syncing
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 18),
            label: Text(syncing ? 'Syncing…' : 'Sync now'),
          ),
          if (counts.rejected > 0)
            TextButton(onPressed: () => confirmClearRejected(context), child: const Text('Clear rejected')),
        ],
      ),
    );
  }

  Future<void> _syncNow(BuildContext context) async {
    final report = await context.read<DashboardCubit>().syncNow();
    final c = report.counts;
    if (!context.mounted) return;
    showToast(
      context,
      report.blockedByFailure
          ? 'Could not reach the server. ${c.pending} still pending; they are safe on this device.'
          : 'Sync finished: ${c.synced} synced, ${c.pending} pending, ${c.rejected} rejected.',
      kind: report.blockedByFailure ? ToastKind.error : ToastKind.success,
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final AttendanceEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = context.read<CompanyClock>();
    final detail = switch (event.status) {
      SyncStatus.rejected => event.lastError == null ? null : formatServerMessage(event.lastError!),
      SyncStatus.pending when event.lastError != null =>
        '${formatServerMessage(event.lastError!)} (attempt ${event.attempts})',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.type == AttendanceType.checkIn ? 'Check-in' : 'Check-out',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${formatDay(event.workDate)}, ${clock.formatTime(event.timestamp)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: event.status == SyncStatus.rejected ? AppColors.danger : AppColors.warning,
                    ),
                  ),
              ],
            ),
          ),
          StatusChip(syncLabel(event.status), syncColor(event.status)),
        ],
      ),
    );
  }
}

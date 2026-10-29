import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/formatters.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets.dart';
import '../../../domain/models.dart';
import 'leave_cubit.dart';
import 'leave_form_screen.dart';

class LeaveScreen extends StatelessWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LeaveCubit>().state;
    return Scaffold(
      appBar: AppBar(title: const Text('Leave')),
      body: RefreshIndicator(
        onRefresh: () => context.read<LeaveCubit>().refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (state.refreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: StatusBanner(
                  tone: BannerTone.warning,
                  icon: state.offline ? Icons.cloud_off_outlined : Icons.sync_problem_outlined,
                  message:
                      '${state.offline ? 'Offline' : state.error}. Showing leave details saved earlier. New requests are saved here and sent automatically when you are back online.',
                ),
              ),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AVAILABLE BALANCE', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 2),
                        Text(
                          state.data.available == null ? '--' : '${state.data.available} days',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: !state.data.hasData
                        ? null
                        : () =>
                              Navigator.of(context)
                                  .push(MaterialPageRoute<void>(builder: (_) => const LeaveFormScreen())),
                    style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionTitle('Requests'),
            if (state.data.queued.isNotEmpty) ...[
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < state.data.queued.length; i++) ...[
                      if (i > 0) const Divider(),
                      _QueuedTile(item: state.data.queued[i]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (state.data.requests.isEmpty && state.data.queued.isEmpty)
              const AppCard(
                child: EmptyState(message: 'You have not applied for leave yet.', icon: Icons.beach_access_outlined),
              )
            else if (state.data.requests.isNotEmpty)
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < state.data.requests.length; i++) ...[
                      if (i > 0) const Divider(),
                      _RequestTile(request: state.data.requests[i]),
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

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});
  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (request.status) {
      LeaveStatus.pending => AppColors.warning,
      LeaveStatus.approved => AppColors.success,
      LeaveStatus.rejected => AppColors.danger,
    };
    final range = request.start == request.end
        ? formatDateOnly(request.start)
        : '${formatDateOnly(request.start)} – ${formatDateOnly(request.end)}';
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
                  '${request.type == LeaveType.casual ? 'Casual' : 'Sick'} · ${request.days} ${request.days == 1 ? 'day' : 'days'}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(range, style: theme.textTheme.bodySmall),
                Text(request.reason, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusChip(request.status.name[0].toUpperCase() + request.status.name.substring(1), color),
        ],
      ),
    );
  }
}

class _QueuedTile extends StatelessWidget {
  const _QueuedTile({required this.item});
  final QueuedLeave item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rejected = item.status == SyncStatus.rejected;
    final range = item.draft.start == item.draft.end
        ? formatDateOnly(item.draft.start!)
        : '${formatDateOnly(item.draft.start!)} – ${formatDateOnly(item.draft.end!)}';
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
                  '${item.draft.type == LeaveType.casual ? 'Casual' : 'Sick'} · ${item.days} ${item.days == 1 ? 'day' : 'days'}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(range, style: theme.textTheme.bodySmall),
                Text(item.draft.reason, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (item.lastError != null)
                  Text(
                    formatServerMessage(item.lastError!),
                    style: theme.textTheme.bodySmall?.copyWith(color: rejected ? AppColors.danger : AppColors.warning),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusChip(syncLabel(item.status), syncColor(item.status)),
              if (rejected)
                TextButton(onPressed: () => context.read<LeaveCubit>().dismiss(item.id), child: const Text('Dismiss')),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/feedback.dart';
import 'dashboard_cubit.dart';

Future<void> confirmClearRejected(BuildContext context) async {
  final cubit = context.read<DashboardCubit>();
  final ok = await confirmDialog(
    context,
    title: 'Clear rejected actions?',
    message: 'Rejected actions were refused by the server and will not be retried. Pending actions are kept.',
    confirmLabel: 'Clear',
  );
  if (!ok) return;
  final removed = await cubit.clearRejected();
  if (context.mounted) {
    showToast(context, 'Cleared $removed rejected ${removed == 1 ? 'action' : 'actions'}.', kind: ToastKind.success);
  }
}

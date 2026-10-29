import 'package:flutter/material.dart';

import 'tokens.dart';

enum ToastKind { success, error, info }

void showToast(BuildContext context, String message, {ToastKind kind = ToastKind.info}) {
  final (icon, color) = switch (kind) {
    ToastKind.success => (Icons.check_circle_outline, AppColors.success),
    ToastKind.error => (Icons.error_outline, AppColors.danger),
    ToastKind.info => (Icons.info_outline, AppColors.accent),
  };
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => _AppDialog(
      icon: const Icon(Icons.help_outline, color: AppColors.accent),
      title: title,
      message: message,
      primaryLabel: confirmLabel,
      onPrimary: () => Navigator.pop(ctx, true),
      secondaryLabel: 'Cancel',
      onSecondary: () => Navigator.pop(ctx, false),
    ),
  );
  return ok ?? false;
}

Future<void> errorDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) => showDialog<void>(
  context: context,
  builder: (ctx) => _AppDialog(
    icon: const Icon(Icons.error_outline, color: AppColors.danger),
    title: title,
    message: message,
    primaryLabel: actionLabel ?? 'Close',
    onPrimary: () {
      Navigator.pop(ctx);
      if (actionLabel != null) onAction?.call();
    },
    secondaryLabel: actionLabel == null ? null : 'Close',
    onSecondary: () => Navigator.pop(ctx),
  ),
);

class _AppDialog extends StatelessWidget {
  const _AppDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });
  final Widget icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: icon,
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
              if (secondaryLabel != null) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

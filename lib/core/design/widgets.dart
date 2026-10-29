import 'package:flutter/material.dart';

import 'tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.md)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelMedium)),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

enum BannerTone { info, warning, danger }

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.message, this.tone = BannerTone.info, this.icon, this.action});
  final String message;
  final BannerTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      BannerTone.info => AppColors.accent,
      BannerTone.warning => AppColors.warning,
      BannerTone.danger => AppColors.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: AppSpacing.sm)],
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Column(
      children: [
        Icon(icon, color: AppColors.textMuted),
        const SizedBox(height: AppSpacing.sm),
        Text(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry, this.offline = false});
  final String message;
  final VoidCallback onRetry;
  final bool offline;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(offline ? Icons.cloud_off_outlined : Icons.error_outline, size: 40, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text(offline ? 'You are offline' : 'Something went wrong', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(minimumSize: const Size(120, 44)),
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

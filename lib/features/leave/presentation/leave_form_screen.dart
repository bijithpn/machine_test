import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/time/company_clock.dart';
import '../../../core/design/feedback.dart';
import '../../../core/design/formatters.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets.dart';
import '../../../core/errors/exceptions.dart';
import '../../../domain/leave_rules.dart';
import '../../../domain/models.dart';
import 'leave_cubit.dart';
import 'leave_form_cubit.dart';

class LeaveFormScreen extends StatefulWidget {
  const LeaveFormScreen({super.key});

  @override
  State<LeaveFormScreen> createState() => _LeaveFormScreenState();
}

class _LeaveFormScreenState extends State<LeaveFormScreen> {
  late final _saved = context.read<LeaveFormCubit>();
  late final _reason = TextEditingController(text: _saved.state.reason);
  late var _type = _saved.state.type;
  late DateTime? _start = _saved.state.start;
  late DateTime? _end = _saved.state.end;
  var _attempted = false;
  var _submitting = false;
  Map<String, String> _serverErrors = {};
  String? _formError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _persist() => _saved.save(_draft);

  LeaveDraft get _draft => LeaveDraft(type: _type, start: _start, end: _end, reason: _reason.text);

  Future<void> _pick({required bool start}) async {
    final today = context.read<CompanyClock>().todayDate;
    final initial = (start ? _start : _end) ?? _start ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final date = DateTime.utc(picked.year, picked.month, picked.day);
    setState(() {
      if (start) {
        _start = date;
        if (_end != null && _end!.isBefore(date)) _end = date;
      } else {
        _end = date;
      }
      _serverErrors = {};
    });
    _persist();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _attempted = true;
      _formError = null;
      _serverErrors = {};
    });
    final errors = _localErrors();
    if (errors.isNotEmpty) return;
    final ok = await confirmDialog(
      context,
      title: 'Submit leave request?',
      message: 'This sends your request for approval and needs a connection.',
      confirmLabel: 'Submit',
    );
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    try {
      await context.read<LeaveCubit>().submit(_draft);
      _saved.reset();
      if (!mounted) return;
      showToast(context, 'Leave request submitted', kind: ToastKind.success);
      Navigator.of(context).pop();
    } on LeaveValidationException catch (e) {
      const known = {'type', 'startDate', 'endDate', 'reason'};
      final fields = {
        for (final f in e.fieldErrors.entries)
          if (known.contains(f.key)) f.key: f.value,
      };
      setState(() {
        _serverErrors = fields;
        _formError = fields.isEmpty || e.fieldErrors.length > fields.length ? e.message ?? e.toString() : e.message;
      });
    } on OfflineException catch (e) {
      setState(() => _formError = e.message);
      errorDialog(context, title: 'You are offline', message: e.message);
    } on ApiException catch (e) {
      setState(() => _formError = e.message);
      showToast(context, e.message, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Map<String, String> _localErrors() {
    final snapshot = context.read<LeaveCubit>().state.data;
    return LeaveRules.validate(
      draft: _draft,
      today: context.read<CompanyClock>().todayDate,
      balance: snapshot.balance ?? 0,
      existing: snapshot.requests,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = context.watch<LeaveCubit>().state.data.balance ?? 0;
    final errors = {..._serverErrors, if (_attempted) ..._localErrors()};
    final days = _start != null && _end != null && !_end!.isBefore(_start!)
        ? LeaveRules.dayCount(_start!, _end!)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_formError != null) ...[
              StatusBanner(tone: BannerTone.danger, icon: Icons.error_outline, message: _formError!),
              const SizedBox(height: AppSpacing.md),
            ],
            Text('Leave type', style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<LeaveType>(
              segments: const [
                ButtonSegment(value: LeaveType.casual, label: Text('Casual')),
                ButtonSegment(value: LeaveType.sick, label: Text('Sick')),
              ],
              selected: {_type},
              onSelectionChanged: _submitting
                  ? null
                  : (s) {
                      setState(() => _type = s.first);
                      _persist();
                    },
              showSelectedIcon: false,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Start date',
                    value: _start,
                    error: errors['startDate'],
                    onTap: _submitting ? null : () => _pick(start: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _DateField(
                    label: 'End date',
                    value: _end,
                    error: errors['endDate'],
                    onTap: _submitting ? null : () => _pick(start: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reason,
              enabled: !_submitting,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                setState(() => _serverErrors.remove('reason'));
                _persist();
              },
              decoration: InputDecoration(labelText: 'Reason', errorText: errors['reason'], alignLabelWithHint: true),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Requested',
                      value: days == null ? '--' : '$days ${days == 1 ? 'day' : 'days'}',
                      over: days != null && days > balance,
                    ),
                  ),
                  Expanded(
                    child: _Stat(label: 'Available', value: '$balance ${balance == 1 ? 'day' : 'days'}'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, this.error});
  final String label;
  final DateTime? value;
  final String? error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(kRadius),
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        errorMaxLines: 3,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
      ),
      child: Text(value == null ? 'Select' : formatDateOnly(value!)),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.over = false});
  final String label;
  final String value;
  final bool over;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 2),
      Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: over ? AppColors.danger : null)),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/feedback.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/exceptions.dart';
import '../../../data/location/location_override_cubit.dart';
import '../../../data/location/location_service.dart';
import '../../../data/remote/hrms_api.dart';

Future<void> showLocationOverride(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => BlocProvider.value(
    value: context.read<LocationOverrideCubit>(),
    child: RepositoryProvider.value(value: context.read<HrmsApi>(), child: const _OverrideForm()),
  ),
);

enum _Target { user, office }

class _OverrideForm extends StatefulWidget {
  const _OverrideForm();

  @override
  State<_OverrideForm> createState() => _OverrideFormState();
}

class _OverrideFormState extends State<_OverrideForm> {
  final _key = GlobalKey<FormState>();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  var _target = _Target.user;
  var _saving = false;
  var _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _load() {
    final s = context.read<LocationOverrideCubit>().state;
    final fix =
        (_target == _Target.user ? s.user : s.office) ??
        LocationFix(AppConfig.officeLatitude, AppConfig.officeLongitude);
    _lat.text = fix.latitude.toString();
    _lng.text = fix.longitude.toString();
  }

  String? _range(String? v, double limit, String name) {
    final n = double.tryParse(v?.trim() ?? '');
    if (n == null) return 'Enter a number';
    return n.abs() > limit ? '$name must be within ±${limit.toInt()}' : null;
  }

  Future<void> _useCurrent() async {
    setState(() => _locating = true);
    try {
      final fix = await DeviceLocationService().currentFix();
      if (!mounted) return;
      _lat.text = fix.latitude.toString();
      _lng.text = fix.longitude.toString();
    } on LocationException catch (e) {
      if (!mounted) return;
      final (label, open) = switch (e.failure) {
        LocationFailure.deniedForever => ('Open app settings', Geolocator.openAppSettings),
        LocationFailure.servicesDisabled => ('Open location settings', Geolocator.openLocationSettings),
        _ => (null, null),
      };
      errorDialog(
        context,
        title: 'Could not get location',
        message: e.message,
        actionLabel: label,
        onAction: open == null ? null : () => open(),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _apply() async {
    if (!_key.currentState!.validate() || _saving) return;
    final lat = double.parse(_lat.text.trim());
    final lng = double.parse(_lng.text.trim());
    final cubit = context.read<LocationOverrideCubit>();
    final api = context.read<HrmsApi>();
    if (_target == _Target.user) {
      cubit.setUser(lat, lng);
      Navigator.pop(context);
      showToast(context, 'Your location set to $lat, $lng.', kind: ToastKind.success);
      return;
    }
    setState(() => _saving = true);
    cubit.setOffice(lat, lng);
    String? failure;
    try {
      await api.setMockOffice(lat, lng);
    } on ApiException catch (e) {
      failure = e.message;
    }
    if (!mounted) return;
    showToast(
      context,
      failure == null
          ? 'Office moved to $lat, $lng.'
          : 'Office moved in the app only. Mock server not updated: $failure',
      kind: failure == null ? ToastKind.success : ToastKind.error,
    );
    Navigator.pop(context);
  }

  void _reset() {
    context.read<LocationOverrideCubit>().reset();
    Navigator.pop(context);
    showToast(context, 'Using real GPS and the configured office.', kind: ToastKind.info);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const decimal = TextInputType.numberWithOptions(decimal: true, signed: true);
    final s = context.watch<LocationOverrideCubit>().state;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Test location', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Your location: ${_describe(s.user, 'real GPS')}\n'
                'Office: ${_describe(s.office, '${AppConfig.officeLatitude}, ${AppConfig.officeLongitude} (default)')}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<_Target>(
                segments: const [
                  ButtonSegment(value: _Target.user, label: Text('Your location')),
                  ButtonSegment(value: _Target.office, label: Text('Office')),
                ],
                selected: {_target},
                onSelectionChanged: (v) => setState(() {
                  _target = v.first;
                  _load();
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _lat,
                keyboardType: decimal,
                decoration: const InputDecoration(labelText: 'Latitude'),
                validator: (v) => _range(v, 90, 'Latitude'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _lng,
                keyboardType: decimal,
                decoration: const InputDecoration(labelText: 'Longitude'),
                validator: (v) => _range(v, 180, 'Longitude'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _locating ? null : _useCurrent,
                  icon: _locating
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 18),
                  label: Text(_locating ? 'Getting location…' : 'Use current location'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: _saving ? null : _apply,
                child: Text(_target == _Target.user ? 'Use as my location' : 'Use as office location'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: _reset, child: const Text('Reset to real GPS and default office')),
            ],
          ),
        ),
      ),
    );
  }

  String _describe(LocationFix? f, String fallback) => f == null ? fallback : '${f.latitude}, ${f.longitude}';
}

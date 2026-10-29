import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rebs_hrms/domain/models.dart';
import 'package:rebs_hrms/features/leave/presentation/leave_form_cubit.dart';

void main() {
  test('unsent leave draft is restored after a restart and cleared by reset', () async {
    final dir = Directory.systemTemp.createTempSync('rebs_hydrated');
    HydratedBloc.storage = await HydratedStorage.build(storageDirectory: HydratedStorageDirectory(dir.path));

    final first = LeaveFormCubit();
    first.save(
      LeaveDraft(
        type: LeaveType.sick,
        start: DateTime.utc(2026, 11, 2),
        end: DateTime.utc(2026, 11, 4),
        reason: 'Flu, resting',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await first.close();

    final restored = LeaveFormCubit().state;
    expect(restored.type, LeaveType.sick);
    expect(restored.start, DateTime.utc(2026, 11, 2));
    expect(restored.end, DateTime.utc(2026, 11, 4));
    expect(restored.reason, 'Flu, resting');

    LeaveFormCubit().reset();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(LeaveFormCubit().state.reason, isEmpty);
  });
}

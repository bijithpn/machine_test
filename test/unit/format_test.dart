import 'package:flutter_test/flutter_test.dart';
import 'package:rebs_hrms/core/design/formatters.dart';

void main() {
  test('legacy geofence rejection from an older server is rewritten with km', () {
    expect(
      formatServerMessage('Recorded location was 361798 m from the office (limit 200 m)'),
      'Outside the office area: you were 361.8 km from the office. Attendance must be within 200 m.',
    );
  });

  test('raw metres of 1 km or more become km, smaller values are untouched', () {
    expect(formatServerMessage('You were 1500 m away'), 'You were 1.5 km away');
    expect(formatServerMessage('You were 850 m away'), 'You were 850 m away');
  });

  test('ISO dates in server text are shown as readable dates', () {
    expect(
      formatServerMessage('Attendance already recorded for 2026-10-29'),
      'Attendance already recorded for 29 Oct 2026',
    );
  });

  test('already formatted messages are left alone', () {
    const m = 'Outside the office area: you were 361.8 km from the office. Attendance must be within 200 m.';
    expect(formatServerMessage(m), m);
  });
}

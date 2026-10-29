import 'package:intl/intl.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

typedef NowFn = DateTime Function();

class CompanyClock {
  CompanyClock({required String timezone, NowFn? now}) : _now = now ?? DateTime.now, _location = _resolve(timezone);

  final NowFn _now;
  final tz.Location _location;
  static var _initialised = false;

  static tz.Location _resolve(String name) {
    if (!_initialised) {
      tzdata.initializeTimeZones();
      _initialised = true;
    }
    return tz.getLocation(name);
  }

  DateTime nowUtc() => _now().toUtc();

  String dateOf(DateTime instant) => DateFormat('yyyy-MM-dd').format(tz.TZDateTime.from(instant, _location));

  String get today => dateOf(nowUtc());

  DateTime get todayDate => parseDate(today);

  static DateTime parseDate(String s) => DateTime.parse('${s}T00:00:00Z');
  static String formatDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String formatTime(DateTime instant) => DateFormat('h:mm a').format(tz.TZDateTime.from(instant, _location));
}

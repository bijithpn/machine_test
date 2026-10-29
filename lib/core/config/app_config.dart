import 'dart:io';

class AppConfig {
  static const _apiOverride = String.fromEnvironment('API_BASE_URL');

  // 10.0.2.2 is the Android emulator's alias for the host machine; the iOS
  // simulator shares the host network. Physical devices need API_BASE_URL.
  static String get apiBaseUrl {
    if (_apiOverride.isNotEmpty) return _apiOverride;
    return Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
  }

  static const employeeId = 'EMP-1042';
  static const companyTimezone = String.fromEnvironment('COMPANY_TZ', defaultValue: 'Asia/Kolkata');
  static final officeLatitude = double.parse(const String.fromEnvironment('OFFICE_LAT', defaultValue: '12.9716'));
  static final officeLongitude = double.parse(const String.fromEnvironment('OFFICE_LNG', defaultValue: '77.5946'));
  static const officeRadiusMeters = 200.0;

  static const simulatedLocation = String.fromEnvironment('SIMULATED_LOCATION');
}

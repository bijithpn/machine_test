import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/exceptions.dart';

class LocationFix {
  const LocationFix(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

abstract class LocationService {
  Future<LocationFix> currentFix();
}

class DeviceLocationService implements LocationService {
  @override
  Future<LocationFix> currentFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        LocationFailure.servicesDisabled,
        'Location services are turned off. Enable them and try again.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailure.deniedForever,
        'Location permission is blocked. Allow it in system settings.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(
        LocationFailure.denied,
        'Location permission is needed to verify you are at the office.',
      );
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return LocationFix(p.latitude, p.longitude);
    } on TimeoutException {
      throw const LocationException(
        LocationFailure.timeout,
        'Timed out while getting your location. Move to an open area and retry.',
      );
    } on LocationServiceDisabledException {
      throw const LocationException(
        LocationFailure.servicesDisabled,
        'Location services are turned off. Enable them and try again.',
      );
    } catch (_) {
      throw const LocationException(LocationFailure.unavailable, 'Your location is currently unavailable.');
    }
  }
}

class SimulatedLocationService implements LocationService {
  const SimulatedLocationService(this.spec);
  final String spec;

  @override
  Future<LocationFix> currentFix() async {
    switch (spec) {
      case 'inside':
        return LocationFix(AppConfig.officeLatitude, AppConfig.officeLongitude);
      case 'outside':
        return LocationFix(AppConfig.officeLatitude + 0.01, AppConfig.officeLongitude);
    }
    final parts = spec.split(',').map((s) => double.tryParse(s.trim())).toList();
    if (parts.length != 2 || parts.contains(null)) {
      throw const LocationException(
        LocationFailure.unavailable,
        'SIMULATED_LOCATION must be inside, outside, or "lat,lng".',
      );
    }
    return LocationFix(parts[0]!, parts[1]!);
  }
}

LocationService createLocationService() => kDebugMode && AppConfig.simulatedLocation.isNotEmpty
    ? const SimulatedLocationService(AppConfig.simulatedLocation)
    : DeviceLocationService();

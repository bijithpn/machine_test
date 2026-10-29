import 'package:hydrated_bloc/hydrated_bloc.dart';

import 'location_service.dart';

class TestLocations {
  const TestLocations({this.user, this.office});
  final LocationFix? user;
  final LocationFix? office;

  bool get isActive => user != null || office != null;
}

class LocationOverrideCubit extends HydratedCubit<TestLocations> {
  LocationOverrideCubit() : super(const TestLocations());

  void setUser(double latitude, double longitude) =>
      emit(TestLocations(user: LocationFix(latitude, longitude), office: state.office));

  void setOffice(double latitude, double longitude) =>
      emit(TestLocations(user: state.user, office: LocationFix(latitude, longitude)));

  void reset() => emit(const TestLocations());

  static LocationFix? _fix(dynamic j) =>
      j == null ? null : LocationFix((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());

  static Map<String, double>? _json(LocationFix? f) => f == null ? null : {'lat': f.latitude, 'lng': f.longitude};

  @override
  TestLocations? fromJson(Map<String, dynamic> json) =>
      TestLocations(user: _fix(json['user']), office: _fix(json['office']));

  @override
  Map<String, dynamic> toJson(TestLocations s) => {'user': _json(s.user), 'office': _json(s.office)};
}

class OverridableLocationService implements LocationService {
  const OverridableLocationService(this._base, this._override);
  final LocationService _base;
  final LocationOverrideCubit _override;

  @override
  Future<LocationFix> currentFix() async => _override.state.user ?? await _base.currentFix();
}

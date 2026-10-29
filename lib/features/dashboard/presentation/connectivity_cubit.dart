import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// Link-layer connectivity only; a `true` here does not prove the API is reachable.
class ConnectivityCubit extends Cubit<bool> {
  ConnectivityCubit(Stream<bool> changes, {bool initial = true}) : super(initial) {
    _sub = changes.listen(emit);
  }

  late final StreamSubscription<bool> _sub;

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}

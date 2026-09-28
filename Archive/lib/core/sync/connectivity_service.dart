import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity;

  ConnectivityService({
    Connectivity? connectivity,
  }) : _connectivity =
      connectivity ?? Connectivity();

  Stream<bool> get connectionStream {
    return _connectivity.onConnectivityChanged.map(
          (results) {
        return results.any(
              (result) =>
          result != ConnectivityResult.none,
        );
      },
    ).distinct();
  }

  Future<bool> get hasConnection async {
    final results =
    await _connectivity.checkConnectivity();

    return results.any(
          (result) =>
      result != ConnectivityResult.none,
    );
  }
}
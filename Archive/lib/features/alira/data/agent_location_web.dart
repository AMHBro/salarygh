import 'dart:async';

import 'package:universal_html/html.dart' as html;

Future<String?> currentAgentLocation() async {
  final geo = html.window.navigator.geolocation;
  try {
    final position = await geo.getCurrentPosition().timeout(
      const Duration(seconds: 12),
    );
    final latitude = position.coords?.latitude;
    final longitude = position.coords?.longitude;
    if (latitude == null || longitude == null) return null;
    return '$latitude,$longitude';
  } catch (_) {
    return null;
  }
}

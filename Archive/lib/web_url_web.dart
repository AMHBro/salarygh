import 'package:flutter_web_plugins/url_strategy.dart';

void configureAppUrl() {
  usePathUrlStrategy();
}

String startRoute() {
  final path = Uri.base.path;
  if (path.endsWith('/shop')) return '/shop';
  if (path.endsWith('/agent')) return '/agent';
  return '/';
}

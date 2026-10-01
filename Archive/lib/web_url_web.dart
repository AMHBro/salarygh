import 'package:flutter_web_plugins/url_strategy.dart';

void configureAppUrl() {
  usePathUrlStrategy();
}

String startRoute() {
  final uri = Uri.base;
  final path = uri.path;
  final fragment = uri.fragment;
  if (path.endsWith('/shop') || fragment.endsWith('/shop')) return '/shop';
  if (path.endsWith('/agent') || fragment.endsWith('/agent')) return '/agent';
  if (path.endsWith('/photos') || fragment.endsWith('/photos')) {
    return '/photos';
  }
  if (path.endsWith('/follow') || fragment.endsWith('/follow')) {
    return '/follow';
  }
  return '/';
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// عنوان السيرفر لكل حاسبة.
///
/// الحاسوبان على الراوتر يستخدمان العنوان المحلي.
/// الحاسبة البعيدة والمتجر والمندوب يستخدمون عنوان الإنترنت إن وُجد.
class ServerEndpoint {
  static const defaultLan = 'http://127.0.0.1:3000/api/v1';

  static const _lanKey = 'server_lan_base';
  static const _internetKey = 'server_internet_base';
  static const _routeKey = 'server_route';

  final FlutterSecureStorage _storage;

  ServerEndpoint({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static final ServerEndpoint instance = ServerEndpoint();

  Future<ServerRoute> read() async {
    final route = await _storage.read(key: _routeKey);
    final lan = await _storage.read(key: _lanKey);
    final internet = await _storage.read(key: _internetKey);
    return ServerRoute(
      useInternet: route == 'internet',
      lanBase: normalizeServerBase(lan) ?? defaultLan,
      internetBase: normalizeServerBase(internet),
    );
  }

  Future<void> save(ServerRoute route) async {
    final lan = normalizeServerBase(route.lanBase) ?? defaultLan;
    final internet = normalizeServerBase(route.internetBase);
    await _storage.write(key: _lanKey, value: lan);
    await _storage.write(key: _routeKey, value: route.useInternet ? 'internet' : 'lan');
    if (internet == null) {
      await _storage.delete(key: _internetKey);
      return;
    }
    await _storage.write(key: _internetKey, value: internet);
  }

  /// عنوان هذه الحاسبة: محلي أو إنترنت حسب اختيارها.
  Future<String> activeBaseUrl() async {
    final route = await read();
    if (route.useInternet && route.internetBase != null) {
      return route.internetBase!;
    }
    return route.lanBase;
  }

  /// المتجر والمندوب: عنوان الإنترنت، وإن لم يُضبط فعنوان الراوتر.
  Future<String> publicBaseUrl() async {
    final route = await read();
    return route.internetBase ?? route.lanBase;
  }
}

class ServerRoute {
  final bool useInternet;
  final String lanBase;
  final String? internetBase;

  const ServerRoute({
    required this.useInternet,
    required this.lanBase,
    required this.internetBase,
  });
}

/// يقبل `192.168.1.8` أو `192.168.1.8:3000` أو رابطاً كاملاً.
String? normalizeServerBase(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }

  var value = text;
  if (!value.contains('://')) {
    value = 'http://$value';
  }

  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) {
    throw StateError('عنوان السيرفر غير صالح.');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw StateError('العنوان يجب أن يبدأ بـ http أو https.');
  }

  final port = uri.hasPort ? ':${uri.port}' : '';
  var path = uri.path;
  if (path.isEmpty || path == '/') {
    path = '/api/v1';
  } else if (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.endsWith('/api/v1')) {
    path = '$path/api/v1';
  }

  return '${uri.scheme}://${uri.host}$port$path';
}

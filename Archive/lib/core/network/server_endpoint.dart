import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// عنوان السيرفر لكل حاسبة.
///
/// الحاسوبان على الراوتر يستخدمان العنوان المحلي.
/// الحاسبة البعيدة والمتجر والمندوب يستخدمون عنوان الإنترنت إن وُجد.
class ServerEndpoint {
  static const defaultLan = 'http://127.0.0.1:3000/api/v1';

  static const defaultInternet =
      'https://salarygh-production.up.railway.app/api/v1';

  static const _lanKey = 'server_lan_base';
  static const _internetKey = 'server_internet_base';
  static const _routeKey = 'server_route';
  static const _publicOfficeKey = 'office_on_public_server';

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
      internetBase: normalizeServerBase(internet) ?? defaultInternet,
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

  /// يثبت المكتب على السيرفر العام مرة واحدة.
  /// بعد ذلك يبقى اختيار «على الراوتر» من الإعدادات سارياً.
  Future<void> ensurePublicOffice() async {
    final applied = await _storage.read(key: _publicOfficeKey);
    if (applied == '1') {
      return;
    }
    final current = await read();
    await save(
      ServerRoute(
        useInternet: true,
        lanBase: current.lanBase,
        internetBase: current.internetBase ?? defaultInternet,
      ),
    );
    await _storage.write(key: _publicOfficeKey, value: '1');
  }

  /// عنوان المكتب: عبر الإنترنت يشمل سيرفر Railway العام.
  Future<String> activeBaseUrl() async {
    final route = await read();
    if (route.useInternet) {
      return route.internetBase ?? defaultInternet;
    }
    return route.lanBase;
  }

  /// المتجر والمندوب يتصلان بعنوان الإنترنت.
  Future<String> publicBaseUrl() async {
    final route = await read();
    return route.internetBase ?? defaultInternet;
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
  var path = uri.path.replaceAll(RegExp(r'/{2,}'), '/');
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isEmpty || path == '/') {
    path = '/api/v1';
  }
  if (!path.endsWith('/api/v1')) {
    path = '$path/api/v1';
  }

  return '${uri.scheme}://${uri.host}$port$path';
}

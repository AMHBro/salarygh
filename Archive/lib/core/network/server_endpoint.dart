import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// عنوان السيرفر لكل حاسبة.
///
/// الحاسوبان على الراوتر يستخدمان العنوان المحلي.
/// الحاسبة البعيدة والمتجر والمندوب يستخدمون عنوان الإنترنت إن وُجد.
class ServerEndpoint {
  static const defaultLan = 'http://127.0.0.1:3000/api/v1';

  static const defaultInternet = 'https://hajecamell.store/api/v1';

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
      internetBase: normalizeServerBase(_dropLegacyHost(internet)) ??
          defaultInternet,
    );
  }

  Future<void> save(ServerRoute route) async {
    final lan = normalizeServerBase(route.lanBase) ?? defaultLan;
    final internet =
        normalizeServerBase(_dropLegacyHost(route.internetBase));
    await _storage.write(key: _lanKey, value: lan);
    await _storage.write(key: _routeKey, value: route.useInternet ? 'internet' : 'lan');
    if (internet == null) {
      await _storage.delete(key: _internetKey);
      return;
    }
    await _storage.write(key: _internetKey, value: internet);
  }

  /// العنوان العام القديم غير منشور، لذلك لا يُفرض على أول تشغيل.
  Future<void> ensurePublicOffice() async {}

  /// عنوان المكتب. ملف server.txt بجانب البرنامج يتقدم على العنوان المحفوظ.
  Future<String> activeBaseUrl() async {
    final bundled = await _bundledServer();
    if (bundled != null) {
      return bundled;
    }
    final route = await read();
    if (route.useInternet) {
      final internet = route.internetBase ?? defaultInternet;
      if (internet != defaultInternet) {
        return internet;
      }
    }
    return route.lanBase;
  }

  Future<String?> _bundledServer() async {
    try {
      final file = File(
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}server.txt',
      );
      if (!await file.exists()) {
        return null;
      }
      for (final raw in await file.readAsLines()) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        return normalizeServerBase(line);
      }
    } catch (_) {}
    return null;
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

/// يتجاهل عنوان Railway القديم حتى تُستخدم النسخة المنشورة الحالية.
String? _dropLegacyHost(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.contains('salarygh-production.up.railway.app')) {
    return null;
  }
  return raw;
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

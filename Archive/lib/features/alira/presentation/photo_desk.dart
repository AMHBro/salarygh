import 'dart:async';

import 'package:universal_html/html.dart' as html;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/network/server_endpoint.dart';
import '../../../core/theme/app_theme.dart';

class PhotoDeskPage extends StatefulWidget {
  const PhotoDeskPage({super.key});

  @override
  State<PhotoDeskPage> createState() => _PhotoDeskPageState();
}

class _PhotoDeskPageState extends State<PhotoDeskPage> {
  final _email = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _search = TextEditingController();
  final _sheetTitle = TextEditingController();
    final _dio = Dio(
    BaseOptions(
      baseUrl: ServerEndpoint.defaultInternet,
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  String? _token;
  String? _message;
  bool _busy = false;
  String _desk = 'products';
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _suppliers = [];
  Set<String> _imageIds = {};

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _search.dispose();
    _sheetTitle.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {
          'email': _email.text.trim(),
          'password': _password.text,
        },
      );
      final token = response.data['accessToken']?.toString() ?? '';
      if (token.isEmpty) {
        throw StateError('تعذر الدخول.');
      }
      setState(() => _token = token);
      await _searchProducts();
    } catch (error) {
      setState(() => _message = 'بيانات الدخول غير صحيحة.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  List<Map<String, dynamic>> _rows(dynamic body) {
    dynamic data = body is Map ? body['data'] : null;
    if (data is Map && data['data'] is List) {
      data = data['data'];
    }
    if (data is! List) {
      return const [];
    }
    return [
      for (final row in data)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  Future<void> _searchSuppliers() async {
    final token = _token;
    if (token == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await _dio.get(
        '/suppliers',
        queryParameters: {
          'search': _search.text.trim(),
          'page': 1,
          'limit': 20,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      setState(() => _suppliers = _rows(response.data));
    } catch (_) {
      setState(() => _message = 'تعذر جلب الموردين.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _searchProducts() async {
    final token = _token;
    if (token == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await _dio.get(
        '/products',
        queryParameters: {
          'search': _search.text.trim(),
          'page': 1,
          'limit': 20,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      var images = <String>{};
      try {
        images = await _imageIdsFromServer();
      } catch (_) {}
      setState(() {
        _products = _rows(response.data);
        _imageIds = images;
      });
    } catch (_) {
      setState(() => _message = 'تعذر جلب المواد.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<Set<String>> _imageIdsFromServer() async {
    final token = _token;
    if (token == null) return {};
    final ids = <String>{};
    var page = 1;
    while (page <= 8) {
      final response = await _dio.get(
        '/products/images',
        queryParameters: {'page': '$page'},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final rows = _rows(response.data);
      if (rows.isEmpty) break;
      for (final row in rows) {
        if ('${row['image_url'] ?? ''}'.trim().isNotEmpty) {
          ids.add('${row['id']}');
        }
      }
      if (rows.length < 30) break;
      page++;
    }
    return ids;
  }

  bool _hasImage(Map<String, dynamic> product) {
    return _imageIds.contains('${product['id']}') ||
        '${product['image_url'] ?? ''}'.trim().isNotEmpty;
  }

  Future<html.File?> _chooseImage() {
    final done = Completer<html.File?>();
    var settled = false;
    final shield = html.DivElement();
    shield.style
      ..position = 'fixed'
      ..top = '0'
      ..left = '0'
      ..width = '100%'
      ..height = '100%'
      ..zIndex = '2147483646'
      ..display = 'flex'
      ..flexDirection = 'column'
      ..backgroundColor = 'rgba(0,0,0,0.45)';
    final bar = html.DivElement();
    bar.style
      ..backgroundColor = '#ffffff'
      ..color = '#1D1D1F'
      ..padding = '16px'
      ..display = 'flex'
      ..alignItems = 'center'
      ..justifyContent = 'space-between'
      ..gap = '12px'
      ..fontSize = '16px';
    final hint = html.SpanElement()..text = 'اضغط اختيار الصورة من المعرض';
    final cancel = html.ButtonElement()..text = 'إلغاء';
    cancel.style
      ..fontSize = '16px'
      ..padding = '8px 14px';
    bar
      ..append(hint)
      ..append(cancel);
    final label = html.LabelElement();
    label.style
      ..flex = '1'
      ..display = 'flex'
      ..alignItems = 'center'
      ..justifyContent = 'center'
      ..color = '#ffffff'
      ..fontSize = '22px'
      ..position = 'relative';
    final caption = html.SpanElement()..text = 'اختيار الصورة';
    caption.style.pointerEvents = 'none';
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.style
      ..position = 'absolute'
      ..top = '0'
      ..left = '0'
      ..width = '100%'
      ..height = '100%'
      ..opacity = '0'
      ..fontSize = '16px';
    label
      ..append(caption)
      ..append(input);
    shield
      ..append(bar)
      ..append(label);
    html.document.body?.append(shield);
    void finish(html.File? file) {
      if (settled) return;
      settled = true;
      shield.remove();
      if (!done.isCompleted) done.complete(file);
    }

    cancel.onClick.listen((event) {
      event.preventDefault();
      event.stopPropagation();
      finish(null);
    });
    final openedAt = DateTime.now();
    input.onChange.listen((_) {
      final files = input.files;
      finish(files != null && files.isNotEmpty ? files.first : null);
    });
    input.on['cancel'].listen((_) {
      if (DateTime.now().difference(openedAt).inMilliseconds < 800) return;
      finish(null);
    });
    input.click();
    return done.future.timeout(const Duration(minutes: 2), onTimeout: () {
      finish(null);
      return null;
    });
  }

  void _tell(String message) {
    setState(() => _message = message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _apiMessage(Object error) {
    if (error is StateError && error.message.isNotEmpty) return error.message;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        final message = data['message'];
        if (message is List && message.isNotEmpty) return '${message.first}';
        return '$message';
      }
      final status = error.response?.statusCode;
      if (status == 413 || status == 400) {
        return 'الصورة كبيرة. اختر صورة أصغر.';
      }
    }
    return 'تعذر حفظ الصورة. تأكد من الاتصال ثم أعد المحاولة.';
  }

  Future<void> _capture(Map<String, dynamic> product) async {
    final file = await _chooseImage();
    if (file == null) {
      if (mounted) _tell('لم يتم اختيار صورة.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final imageUrl = await _compress(file);
      await _dio.patch(
        '/products/${product['id']}',
        data: {'image_url': imageUrl},
        options: Options(headers: {'Authorization': 'Bearer ${_token!}'}),
      );
      _tell('حُفظت صورة ${product['name_ar'] ?? ''}.');
      await _searchProducts();
    } catch (error) {
      _tell(_apiMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _clearProductImage(Map<String, dynamic> product) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _dio.patch(
        '/products/${product['id']}',
        data: {'image_url': null},
        options: Options(headers: {'Authorization': 'Bearer ${_token!}'}),
      );
      setState(() => _message = 'حُذفت صورة ${product['name_ar'] ?? ''}.');
      await _searchProducts();
    } catch (error) {
      setState(() => _message = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _captureSupplier(Map<String, dynamic> supplier) async {
    final title = _sheetTitle.text.trim().isEmpty
        ? 'صورة ${DateTime.now().day}-${DateTime.now().month}'
        : _sheetTitle.text.trim();
    final file = await _chooseImage();
    if (file == null) {
      if (mounted) _tell('لم يتم اختيار صورة.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final imageUrl = await _compress(file);
      await _dio.post(
        '/suppliers/${supplier['id']}/sheets',
        data: {
          'title': title,
          'image_url': imageUrl,
        },
        options: Options(headers: {'Authorization': 'Bearer ${_token!}'}),
      );
      _sheetTitle.clear();
      _tell('حُفظت الصورة في مجلد ${supplier['name'] ?? ''}.');
    } catch (error) {
      _tell(_apiMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String> _compress(html.File file) async {
    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    await reader.onLoad.first.timeout(const Duration(seconds: 25));
    final raw = reader.result as String;
    final image = html.ImageElement()..src = raw;
    image.style
      ..position = 'fixed'
      ..left = '-4000px'
      ..top = '0';
    html.document.body?.append(image);
    try {
      await image.onLoad.first.timeout(const Duration(seconds: 25));
      var width = image.naturalWidth;
      var height = image.naturalHeight;
      if (width < 2 || height < 2) {
        return _usableRaw(raw);
      }
      const maxSide = 960;
      if (width > maxSide || height > maxSide) {
        final scale = maxSide / (width > height ? width : height);
        width = (width * scale).round();
        height = (height * scale).round();
      }
      final canvas = html.CanvasElement()
        ..width = width
        ..height = height;
      canvas.context2D.drawImageScaled(image, 0, 0, width, height);
      final url = canvas.toDataUrl('image/jpeg', 0.72);
      if (url.startsWith('data:image/') && url.length <= 1400000) return url;
      final smaller = canvas.toDataUrl('image/jpeg', 0.45);
      if (smaller.startsWith('data:image/') && smaller.length <= 1400000) {
        return smaller;
      }
      return _usableRaw(raw);
    } on TimeoutException {
      return _usableRaw(raw);
    } finally {
      image.remove();
    }
  }

  String _usableRaw(String raw) {
    final ok = raw.startsWith('data:image/jpeg') ||
        raw.startsWith('data:image/png') ||
        raw.startsWith('data:image/webp');
    if (ok && raw.length <= 1400000) return raw;
    throw StateError('صيغة الصورة غير مدعومة. اختر صورة JPG من المعرض.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('صور المنتجات والموردين')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_token == null) ...[
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'اسم الدخول'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور'),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: const Text('دخول المدير'),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _desk == 'products'
                      ? FilledButton(
                          onPressed: _busy ? null : _searchProducts,
                          child: const Text('المنتجات'),
                        )
                      : OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() => _desk = 'products');
                                  _searchProducts();
                                },
                          child: const Text('المنتجات'),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _desk == 'suppliers'
                      ? FilledButton(
                          onPressed: _busy ? null : _searchSuppliers,
                          child: const Text('الموردون'),
                        )
                      : OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() => _desk = 'suppliers');
                                  _searchSuppliers();
                                },
                          child: const Text('الموردون'),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _desk == 'products'
                  ? 'الصورة تُحفظ مع المادة في قاعدة النظام على السيرفر. من الأيقونة تبدّلها، ومن الحذف تزيلها.'
                  : 'صورة المورد تُحفظ في مجلده داخل قاعدة النظام، مو على الهاتف. اختر صورة من المعرض أو الكاميرا.',
            ),
            const SizedBox(height: 12),
            if (_desk == 'suppliers') ...[
              TextField(
                controller: _sheetTitle,
                decoration: const InputDecoration(
                  hintText: 'اسم الصورة، مثل: قائمة أيلول',
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: _desk == 'products' ? 'اسم المادة' : 'اسم المورد',
              ),
              onSubmitted: (_) =>
                  _desk == 'products' ? _searchProducts() : _searchSuppliers(),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _desk == 'products'
                      ? _searchProducts()
                      : _searchSuppliers(),
              child: const Text('بحث'),
            ),
            const SizedBox(height: 12),
            if (_desk == 'products')
              for (final product in _products)
                Card(
                  child: ListTile(
                    title: Text('${product['name_ar'] ?? ''}'),
                    subtitle: Text(_hasImage(product) ? 'فيها صورة' : 'بدون صورة'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'تبديل الصورة',
                          onPressed: _busy ? null : () => _capture(product),
                          icon: const Icon(Icons.add_a_photo_outlined),
                        ),
                        IconButton(
                          tooltip: 'حذف الصورة',
                          onPressed: _busy || !_hasImage(product)
                              ? null
                              : () => _clearProductImage(product),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                )
            else
              for (final supplier in _suppliers)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${supplier['name'] ?? ''}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _captureSupplier(supplier),
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('رفع صورة'),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
        ],
      ),
    );
  }
}

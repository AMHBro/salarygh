import 'dart:html' as html;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

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
      baseUrl: 'https://salarygh-production.up.railway.app/api/v1',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
    ),
  );

  String? _token;
  String? _message;
  bool _busy = false;
  String _desk = 'products';
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _suppliers = [];

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
      setState(() => _products = _rows(response.data));
    } catch (_) {
      setState(() => _message = 'تعذر جلب المواد.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _capture(Map<String, dynamic> product) async {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.setAttribute('capture', 'environment');
    input.click();
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) {
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
      setState(() => _message = 'حُفظت صورة ${product['name_ar'] ?? ''}.');
    } catch (_) {
      setState(() => _message = 'تعذر حفظ الصورة. انشر تحديث السيرفر ثم أعد المحاولة.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _captureSupplier(Map<String, dynamic> supplier) async {
    final title = _sheetTitle.text.trim();
    if (title.isEmpty) {
      setState(() => _message = 'اكتب اسماً للصورة، مثل: قائمة أيلول.');
      return;
    }
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.setAttribute('capture', 'environment');
    input.click();
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) {
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
      setState(() => _message = 'حُفظت الصورة في مجلد ${supplier['name'] ?? ''}.');
    } catch (_) {
      setState(() => _message = 'تعذر حفظ صورة المورد. انشر تحديث السيرفر ثم أعد المحاولة.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String> _compress(html.File file) async {
    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    await reader.onLoad.first;
    final image = html.ImageElement()..src = reader.result as String;
    await image.onLoad.first;
    final canvas = html.CanvasElement();
    var width = image.width ?? 1;
    var height = image.height ?? 1;
    const maxSide = 960;
    if (width > maxSide || height > maxSide) {
      final scale = maxSide / (width > height ? width : height);
      width = (width * scale).round();
      height = (height * scale).round();
    }
    canvas
      ..width = width
      ..height = height;
    canvas.context2D.drawImageScaled(image, 0, 0, width, height);
    final url = canvas.toDataUrl('image/jpeg', 0.72);
    if (url.length > 1400000) {
      throw StateError('الصورة كبيرة.');
    }
    return url;
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
                  ? 'اختر المادة ثم التقط صورتها. تُحفظ الصورة على المادة في النظام الأساسي.'
                  : 'اكتب اسم الصورة، ثم اختر المورد والتقطها. تنزل داخل مجلده في النظام الأساسي.',
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
                    trailing: IconButton(
                      tooltip: 'التقاط صورة',
                      onPressed: _busy ? null : () => _capture(product),
                      icon: const Icon(Icons.add_a_photo_outlined),
                    ),
                  ),
                )
            else
              for (final supplier in _suppliers)
                Card(
                  child: ListTile(
                    title: Text('${supplier['name'] ?? ''}'),
                    trailing: IconButton(
                      tooltip: 'إضافة صورة للمجلد',
                      onPressed: _busy ? null : () => _captureSupplier(supplier),
                      icon: const Icon(Icons.add_a_photo_outlined),
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

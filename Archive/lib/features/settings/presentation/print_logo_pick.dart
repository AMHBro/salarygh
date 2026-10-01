import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// يفتح مربع اختيار الصورة ويحوّلها إلى Data URL ليُحفظ داخل print_settings.
Future<String?> pickPrintImage({String title = 'صورة المطبوعات'}) async {
  const group = XTypeGroup(
    label: 'images',
    extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    mimeTypes: ['image/png', 'image/jpeg', 'image/webp', 'image/bmp'],
  );
  final file = await openFile(
    acceptedTypeGroups: const [group],
    confirmButtonText: 'اختيار',
  );
  if (file == null) {
    return null;
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    return null;
  }
  if (bytes.length > 1500000) {
    throw StateError('الصورة أكبر من 1.5 ميغابايت.');
  }
  final name = file.name.toLowerCase();
  final mime = name.endsWith('.png')
      ? 'image/png'
      : name.endsWith('.webp')
          ? 'image/webp'
          : name.endsWith('.bmp')
              ? 'image/bmp'
              : 'image/jpeg';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

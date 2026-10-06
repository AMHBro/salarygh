import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> saveDailyProductPhoto({
  required String name,
  required String imageUrl,
  required DateTime savedAt,
}) async {
  final comma = imageUrl.indexOf(',');
  if (!imageUrl.startsWith('data:image/') || comma < 0) return;
  final bytes = base64Decode(imageUrl.substring(comma + 1).replaceAll(RegExp(r'\s'), ''));
  final day = _stamp(savedAt);
  final safe = _safeName(name);
  final directory = Directory(
    p.join(_home, 'Documents', 'SaylerInbox', day, 'منتجات'),
  );
  await directory.create(recursive: true);
  await File(p.join(directory.path, '$safe.jpg')).writeAsBytes(bytes);
}

String get _home => Platform.environment['USERPROFILE'] ?? Directory.current.path;

String _stamp(DateTime savedAt) {
  final local = savedAt.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

String _safeName(String value) {
  final cleaned = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
  return cleaned.isEmpty ? 'بدون اسم' : cleaned;
}

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Directory? storeOutboxDirectoryOverride;

Future<File> _queueFile() async {
  final directory = storeOutboxDirectoryOverride ?? await getApplicationSupportDirectory();
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return File('${directory.path}${Platform.pathSeparator}store_outbox.json');
}

Future<List<Map<String, dynamic>>> readStoreOutbox() async {
  final file = await _queueFile();
  if (!await file.exists()) return [];
  final raw = jsonDecode(await file.readAsString());
  if (raw is! List) return [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Future<void> writeStoreOutbox(List<Map<String, dynamic>> items) async {
  final file = await _queueFile();
  await file.writeAsString(jsonEncode(items));
}

import 'dart:convert';

import 'package:file_selector/file_selector.dart';

const _jsonGroup = XTypeGroup(
  label: 'JSON',
  extensions: ['json'],
  mimeTypes: ['application/json'],
);

Future<bool> saveBackupFile(String name, String contents) async {
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: const [_jsonGroup],
    confirmButtonText: 'حفظ النسخة',
  );
  if (location == null) {
    return false;
  }
  final file = XFile.fromData(
    utf8.encode(contents),
    mimeType: 'application/json',
    name: name,
  );
  await file.saveTo(location.path);
  return true;
}

Future<String?> pickBackupText() async {
  final file = await openFile(
    acceptedTypeGroups: const [_jsonGroup],
    confirmButtonText: 'اختيار النسخة',
  );
  if (file == null) {
    return null;
  }
  return file.readAsString();
}

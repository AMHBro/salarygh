import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class SupplierSheet {
  final File file;
  final String title;
  final DateTime savedAt;

  const SupplierSheet({
    required this.file,
    required this.title,
    required this.savedAt,
  });
}

class SupplierFolder {
  static Directory directoryFor(String supplierName) {
    final home = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    final safe = _safeName(supplierName);
    return Directory(p.join(home, 'Documents', 'SaylerSuppliers', safe));
  }

  static Future<List<SupplierSheet>> list(String supplierName) async {
    final directory = directoryFor(supplierName);
    if (!await directory.exists()) {
      return const [];
    }
    final sheets = <SupplierSheet>[];
    for (final entity in directory.listSync()) {
      if (entity is! File) {
        continue;
      }
      final extension = p.extension(entity.path).toLowerCase();
      if (extension != '.jpg' &&
          extension != '.jpeg' &&
          extension != '.png' &&
          extension != '.webp') {
        continue;
      }
      final name = p.basenameWithoutExtension(entity.path);
      final savedAt = await entity.lastModified();
      sheets.add(SupplierSheet(file: entity, title: name, savedAt: savedAt));
    }
    sheets.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return sheets;
  }

  static Future<File> save({
    required String supplierName,
    required String title,
    required XFile source,
  }) async {
    final directory = directoryFor(supplierName);
    await directory.create(recursive: true);
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final extension = p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path);
    final fileName = '$stamp ${_safeName(title)}$extension';
    final destination = File(p.join(directory.path, fileName));
    await destination.writeAsBytes(await source.readAsBytes());
    return destination;
  }

  static Future<void> saveDataUrl({
    required String sheetId,
    required String supplierName,
    required String title,
    required String imageUrl,
    required DateTime savedAt,
  }) async {
    if (await _alreadySaved(sheetId)) {
      return;
    }
    final comma = imageUrl.indexOf(',');
    if (!imageUrl.startsWith('data:image/') || comma < 0) {
      return;
    }
    final bytes = base64Decode(imageUrl.substring(comma + 1));
    final directory = directoryFor(supplierName);
    await directory.create(recursive: true);
    final stamp =
        '${savedAt.year}-${savedAt.month.toString().padLeft(2, '0')}-${savedAt.day.toString().padLeft(2, '0')}';
    final shortId = sheetId.length <= 8 ? sheetId : sheetId.substring(0, 8);
    final fileName = '$stamp ${_safeName(title)}-$shortId.jpg';
    await File(p.join(directory.path, fileName)).writeAsBytes(bytes);
    final home = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    final dayFolder = Directory(
      p.join(home, 'Documents', 'SaylerInbox', stamp, 'موردون', _safeName(supplierName)),
    );
    await dayFolder.create(recursive: true);
    await File(p.join(dayFolder.path, fileName)).writeAsBytes(bytes);
    await _remember(sheetId);
  }

  static File get _ledger {
    final home = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    return File(p.join(home, 'Documents', 'SaylerSuppliers', '.imported-ids'));
  }

  static Future<bool> _alreadySaved(String sheetId) async {
    final file = _ledger;
    if (!await file.exists()) {
      return false;
    }
    final lines = (await file.readAsString()).split('\n');
    return lines.contains(sheetId);
  }

  static Future<void> _remember(String sheetId) async {
    final file = _ledger;
    await file.parent.create(recursive: true);
    await file.writeAsString('$sheetId\n', mode: FileMode.append);
  }

  static Future<void> reveal(String path) {
    return Process.run('explorer', [path]);
  }

  static String _safeName(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    return cleaned.isEmpty ? 'بدون اسم' : cleaned;
  }
}

Future<void> showSupplierFolderDialog(
  BuildContext context,
  String supplierName,
) async {
  final name = supplierName.trim();
  if (name.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اكتب اسم المورد أولاً.')),
    );
    return;
  }
  final titleController = TextEditingController();
  var sheets = await SupplierFolder.list(name);
  if (!context.mounted) {
    titleController.dispose();
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text('مجلد $name'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        hintText: 'اسم الصورة، مثل: قائمة أيلول',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final title = titleController.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('اكتب اسماً للصورة.')),
                            );
                            return;
                          }
                          const group = XTypeGroup(
                            label: 'images',
                            extensions: ['jpg', 'jpeg', 'png', 'webp'],
                          );
                          final file = await openFile(acceptedTypeGroups: [group]);
                          if (file == null) {
                            return;
                          }
                          await SupplierFolder.save(
                            supplierName: name,
                            title: title,
                            source: file,
                          );
                          sheets = await SupplierFolder.list(name);
                          titleController.clear();
                          setDialogState(() {});
                        },
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('إضافة صورة'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (sheets.isEmpty)
                      const Text(
                        'لا توجد صور بعد. الصورة تُحفظ بتاريخ اليوم داخل مجلد المورد.',
                        style: TextStyle(fontSize: 12),
                      )
                    else
                      SizedBox(
                        height: 220,
                        child: ListView(
                          children: [
                            for (final sheet in sheets)
                              ListTile(
                                dense: true,
                                title: Text(
                                  sheet.title,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${sheet.savedAt.year}-${sheet.savedAt.month.toString().padLeft(2, '0')}-${sheet.savedAt.day.toString().padLeft(2, '0')}',
                                ),
                                onTap: () => SupplierFolder.reveal(sheet.file.path),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final directory = SupplierFolder.directoryFor(name);
                    await directory.create(recursive: true);
                    await SupplierFolder.reveal(directory.path);
                  },
                  child: const Text('فتح المجلد'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  titleController.dispose();
}

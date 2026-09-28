import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// يكتب الورقة ويفتحها في المتصفح، والصفحة تستدعي مربع طباعة النظام.
void openPrintWindow(String documentHtml) {
  Future<void>(() async {
    final directory = await getTemporaryDirectory();
    final file = File(
      p.join(
        directory.path,
        'sayler-print-${DateTime.now().millisecondsSinceEpoch}.html',
      ),
    );
    await file.writeAsString(documentHtml, flush: true);

    if (Platform.isWindows) {
      final path = file.path.replaceAll("'", "''");
      await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "Start-Process -FilePath '$path'",
        ],
      );
      return;
    }

    if (Platform.isMacOS) {
      await Process.run('open', [file.path]);
      return;
    }

    await Process.run('xdg-open', [file.path]);
  });
}

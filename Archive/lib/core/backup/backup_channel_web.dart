import 'package:universal_html/html.dart' as html;

Future<void> saveBackupFile(String name, String contents) async {
  final blob = html.Blob([contents], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = name
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<String?> pickBackupText() async {
  final input = html.FileUploadInputElement()..accept = '.json,application/json';
  input.click();
  await input.onChange.first;
  final file = input.files?.first;
  if (file == null) {
    return null;
  }
  final reader = html.FileReader();
  reader.readAsText(file);
  await reader.onLoad.first;
  final result = reader.result;
  return result is String ? result : null;
}

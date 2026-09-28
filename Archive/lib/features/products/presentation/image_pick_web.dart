import 'dart:html' as html;

Future<String?> pickProductImage() async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.click();
  await input.onChange.first;
  final file = input.files?.first;
  if (file == null) return null;
  if (file.size > 1500000) {
    throw StateError('الصورة أكبر من 1.5 ميغابايت');
  }
  final reader = html.FileReader();
  final done = reader.onLoad.first;
  reader.readAsDataUrl(file);
  await done;
  final result = reader.result;
  return result is String ? result : null;
}

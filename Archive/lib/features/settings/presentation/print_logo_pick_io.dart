import 'dart:convert';
import 'dart:io';

Future<String?> pickPrintLogo() async {
  final result = await Process.run(
    'powershell',
    [
      '-NoProfile',
      '-STA',
      '-Command',
      r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = "Images|*.png;*.jpg;*.jpeg;*.webp;*.bmp"
$dialog.Title = "شعار المكتب"
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output $dialog.FileName
}
''',
    ],
  );
  final path = '${result.stdout}'.trim();
  if (path.isEmpty || !File(path).existsSync()) {
    return null;
  }
  final bytes = await File(path).readAsBytes();
  if (bytes.length > 1500000) {
    throw StateError('الشعار أكبر من 1.5 ميغابايت.');
  }
  final lower = path.toLowerCase();
  final mime = lower.endsWith('.png')
      ? 'image/png'
      : lower.endsWith('.webp')
          ? 'image/webp'
          : lower.endsWith('.bmp')
              ? 'image/bmp'
              : 'image/jpeg';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

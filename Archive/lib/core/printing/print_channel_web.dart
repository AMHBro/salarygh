import 'package:universal_html/html.dart' as html;

void openPrintWindow(String documentHtml) {
  final blob = html.Blob([documentHtml], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
}

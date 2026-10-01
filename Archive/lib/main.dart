import 'package:flutter/material.dart';

import 'app.dart';
import 'web_url.dart';

export 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppUrl();
  runApp(const SalesApp());
}
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sales_system/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SalesApp يبني من نقطة الدخول', (tester) async {
    await tester.pumpWidget(const SalesApp());
    expect(find.byType(SalesApp), findsOneWidget);
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

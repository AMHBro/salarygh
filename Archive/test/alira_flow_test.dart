import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_system/features/alira/data/alira_catalog.dart';
import 'package:sales_system/features/alira/presentation/agent_app.dart';
import 'package:sales_system/features/alira/presentation/shop_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AliraCatalog.forceMock = true;
    AliraCatalog.applyMock();
  });

  Future<void> pumpApp(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('تطبيق المندوب: بحث وزيارة وذمم وكشف وفاتورة وإغلاق', (tester) async {
    await pumpApp(tester, const AliraAgentApp());

    expect(find.text('المسارات'), findsOneWidget);
    expect(find.text('تطبيق المندوب · الزيارات والتحصيل'), findsOneWidget);
    expect(find.text('20 سبتمبر'), findsOneWidget);
    expect(find.text('محلات الحاج كامل ابو محمد جميلة'), findsWidgets);
    expect(find.text('32'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('متابعة'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'الشارقة');
    await tester.pump();
    expect(find.text('مكتب الشارقة جميلة'), findsOneWidget);
    expect(find.text('مكتب الرسل شارع الميزان'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();

    await tester.tap(find.text('متابعة'));
    await tester.pump();
    expect(find.text('00:09'), findsOneWidget);
    expect(find.text('الرصيد IQD 4,540,000'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'مقبوضات')).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'فعاليات')).onPressed, isNull);

    await tester.tap(find.text('أعمار الذمم'));
    await tester.pump();
    expect(find.text('فاتورة 27027'), findsOneWidget);
    expect(find.text('فاتورة 28470'), findsOneWidget);
    expect(find.text('المجموع IQD 4,540,000 · 2 فواتير'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump();

    await tester.tap(find.text('كشف حساب'));
    await tester.pump();
    expect(find.text('مدين IQD 6,990,000'), findsOneWidget);
    expect(find.text('دائن IQD 2,450,000'), findsOneWidget);
    expect(find.text('+2,450,000'), findsOneWidget);
    expect(find.text('-570,000'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump();

    await tester.tap(find.text('فاتورة جديدة'));
    await tester.pump();
    expect(find.text('مواد غذائية'), findsWidgets);
    await tester.tap(find.text('مواد غذائية').first);
    await tester.pump();
    expect(find.text('أضف مواد إلى السلة'), findsOneWidget);

    final firstAdd = find.byIcon(Icons.add).first;
    await tester.ensureVisible(firstAdd);
    await tester.tap(firstAdd);
    await tester.pump();

    TextField paidField() {
      return tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) => widget is TextField && widget.decoration?.labelText == 'المدفوع',
        ),
      );
    }

    expect(paidField().readOnly, isTrue);
    expect(paidField().controller!.text, '0');

    await tester.tap(find.text('نقداً'));
    await tester.pump();
    expect(paidField().readOnly, isTrue);
    expect(paidField().controller!.text, '8000');

    await tester.tap(find.text('جزئي'));
    await tester.pump();
    expect(paidField().readOnly, isFalse);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == 'المدفوع',
      ),
      '1000',
    );
    await tester.pump();

    await tester.tap(find.text('إرسال للمكتب'));
    await tester.pump();
    expect(find.text('تم الإرسال'), findsOneWidget);
    expect(find.textContaining('asr_'), findsOneWidget);
    expect(find.textContaining('بانتظار موافقة المكتب'), findsOneWidget);

    await tester.tap(find.text('العودة للزيارة'));
    await tester.pump();
    expect(find.text('تم تسجيل حركة / طلبات'), findsOneWidget);
    expect(find.text('طلبات بانتظار: 1'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ستُغلق الزيارة الحالية دون حفظ أي حركة.'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('المسارات'), findsOneWidget);
    expect(find.text('متابعة'), findsNothing);

    final secondOpen = find.text('فتح زيارة').at(1);
    await tester.ensureVisible(secondOpen);
    await tester.pump();
    await tester.tap(secondOpen);
    await tester.pump();
    await tester.tap(find.text('تأجيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ستُنقل إلى المؤجلة ويمكن استئنافها لاحقاً من المسارات.'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('فتح زيارة').first);
    await tester.pump();
    await tester.tap(find.text('إتمام الزيارة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('سيتم إرسال حالة الإتمام إلى الباكند.'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('المسارات'), findsOneWidget);
  });

  testWidgets('متجر الزبون: كمية وسلة ورفض ناقص ثم رقم الطلب', (tester) async {
    await pumpApp(tester, const AliraShopApp());

    expect(find.text('المتجر'), findsOneWidget);
    expect(find.text('سعر المفرد'), findsOneWidget);
    expect(find.text('مواد غذائية'), findsWidgets);
    await tester.tap(find.text('إضافة').first);
    await tester.pump();
    expect(find.text('1 مواد'), findsOneWidget);
    expect(find.text('8,000 د.ع'), findsWidgets);

    await tester.tap(find.text('مراجعة وإرسال الطلب'));
    await tester.pump();
    await tester.tap(find.text('متابعة البيانات'));
    await tester.pump();
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pump();
    expect(
      find.text('أدخل الاسم والعنوان ورقم هاتف مكتمل، مع مواد في السلة.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == 'الاسم'),
      'سارة',
    );
    await tester.enterText(
      find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == 'العنوان'),
      'الكرادة',
    );
    await tester.enterText(
      find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == 'الهاتف'),
      '0770',
    );
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pump();
    expect(
      find.text('أدخل الاسم والعنوان ورقم هاتف مكتمل، مع مواد في السلة.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == 'الهاتف'),
      '07701234567',
    );
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pump();
    expect(find.text('وصل طلبك'), findsOneWidget);
    expect(find.textContaining('رقم الطلب ord_'), findsOneWidget);
    expect(find.textContaining('IQD 8,000'), findsOneWidget);
    expect(find.textContaining('الكرادة'), findsOneWidget);
    expect(find.textContaining('07701234567'), findsOneWidget);

    await tester.tap(find.text('طلب جديد'));
    await tester.pump();
    expect(find.text('0 مواد'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'مراجعة وإرسال الطلب')).onPressed,
      isNull,
    );
  });
}

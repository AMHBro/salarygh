import 'package:flutter_test/flutter_test.dart';
import 'package:sales_system/core/auth/auth_user.dart';
import 'package:sales_system/core/auth/local_credentials.dart';

void main() {
  test('رأس المال والتقارير للمدير والمسؤول فقط', () {
    expect(canOpenFinanceReports('MANAGER'), isTrue);
    expect(canOpenFinanceReports('admin'), isTrue);
    expect(canOpenFinanceReports('SUPER_ADMIN'), isTrue);
    expect(canOpenFinanceReports('CASHIER'), isFalse);
    expect(canOpenFinanceReports('WAREHOUSE'), isFalse);
    expect(canOpenFinanceReports('REP'), isFalse);
    expect(canOpenFinanceReports(''), isFalse);
    expect(canOpenFinanceReports(null), isFalse);
  });

  test('الدخول المحلي يطابق التجزئة ويرفض كلمة مختلفة وانتهاء المهلة', () async {
    final box = <String, String>{};
    final now = DateTime.utc(2026, 9, 27, 12);
    final credentials = LocalCredentials(
      memory: box,
      now: () => now,
    );

    await credentials.remember(
      login: 'Cashier@Station.Sayler.app',
      password: 'secret-pass',
      user: const AuthUser(
        id: 'user-1',
        email: 'cashier@station.sayler.app',
        name: 'الصندوق',
        role: 'CASHIER',
      ),
    );

    final session = await credentials.openOffline(
      login: 'cashier@station.sayler.app',
      password: 'secret-pass',
    );
    expect(session?.user.role, 'CASHIER');
    expect(session?.user.id, 'user-1');

    final wrong = await credentials.openOffline(
      login: 'cashier@station.sayler.app',
      password: 'other',
    );
    expect(wrong, isNull);

    final expired = LocalCredentials(
      memory: box,
      now: () => now.add(const Duration(days: 15)),
    );
    final late = await expired.openOffline(
      login: 'cashier@station.sayler.app',
      password: 'secret-pass',
    );
    expect(late, isNull);
  });
}
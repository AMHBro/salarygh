import '../models/customer_model.dart';

class MockCustomersRepository {
  const MockCustomersRepository();

  List<CustomerModel> getCustomers() {
    return [
      CustomerModel(
        id: 1,
        name: 'أحمد محمد',
        phone: '07701234567',
        address: 'بغداد - المنصور',
        totalPurchases: 3450000,
        totalPaid: 2900000,
        balance: 550000,
        invoicesCount: 18,
        lastPurchaseDate: DateTime(2026, 8, 18),
        notes: 'زبون دائم',
      ),
      CustomerModel(
        id: 2,
        name: 'شركة النور',
        phone: '07801234567',
        address: 'بغداد - الكرادة',
        totalPurchases: 12650000,
        totalPaid: 11200000,
        balance: 1450000,
        invoicesCount: 31,
        lastPurchaseDate: DateTime(2026, 8, 17),
        notes: 'زبون جملة',
      ),
      CustomerModel(
        id: 3,
        name: 'محمد علي',
        phone: '07501234567',
        address: 'بغداد - الأعظمية',
        totalPurchases: 1850000,
        totalPaid: 1850000,
        balance: 0,
        invoicesCount: 12,
        lastPurchaseDate: DateTime(2026, 8, 16),
      ),
      CustomerModel(
        id: 4,
        name: 'مكتب الرافدين',
        phone: '07711234567',
        address: 'بغداد - الجادرية',
        totalPurchases: 8250000,
        totalPaid: 7100000,
        balance: 1150000,
        invoicesCount: 26,
        lastPurchaseDate: DateTime(2026, 8, 15),
        notes: 'تعامل آجل',
      ),
      CustomerModel(
        id: 5,
        name: 'علي حسن',
        phone: '07811234567',
        address: 'بغداد - زيونة',
        totalPurchases: 950000,
        totalPaid: 700000,
        balance: 250000,
        invoicesCount: 7,
        lastPurchaseDate: DateTime(2026, 8, 14),
      ),
    ];
  }
}
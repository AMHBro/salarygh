import '../models/supplier_model.dart';

class MockSuppliersRepository {
  const MockSuppliersRepository();

  List<SupplierModel> getSuppliers() {
    return [
      SupplierModel(
        id: 1,
        name: 'شركة النور للتجارة',
        phone: '07701234567',
        address: 'بغداد - المنصور',
        notes: 'مورد رئيسي',
        totalPurchases: 18450000,
        totalPaid: 16000000,
        balance: 2450000,
        invoicesCount: 24,
        lastPurchaseDate: DateTime(2026, 8, 17),
      ),
      SupplierModel(
        id: 2,
        name: 'شركة الرافدين',
        phone: '07801234567',
        address: 'بغداد - الكرادة',
        totalPurchases: 11200000,
        totalPaid: 11200000,
        balance: 0,
        invoicesCount: 16,
        lastPurchaseDate: DateTime(2026, 8, 15),
      ),
      SupplierModel(
        id: 3,
        name: 'مؤسسة بغداد للتجهيز',
        phone: '07501234567',
        address: 'بغداد - جميلة',
        totalPurchases: 8650000,
        totalPaid: 7200000,
        balance: 1450000,
        invoicesCount: 11,
        lastPurchaseDate: DateTime(2026, 8, 12),
      ),
      SupplierModel(
        id: 4,
        name: 'شركة الشرق',
        phone: '07711234567',
        address: 'بغداد',
        totalPurchases: 4200000,
        totalPaid: 3800000,
        balance: 400000,
        invoicesCount: 7,
        lastPurchaseDate: DateTime(2026, 8, 8),
      ),
    ];
  }
}
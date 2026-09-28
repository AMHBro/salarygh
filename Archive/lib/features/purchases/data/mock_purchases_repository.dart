import '../../suppliers/data/mock_suppliers_repository.dart';
import '../../suppliers/models/supplier_model.dart';
import '../models/purchase_model.dart';

class MockPurchasesRepository {
  final MockSuppliersRepository _suppliersRepository =
  const MockSuppliersRepository();

  List<SupplierModel> getSuppliers() {
    return _suppliersRepository.getSuppliers();
  }

  List<String> getWarehouses() {
    return const [
      'المخزن الرئيسي',
      'مخزن المنصور',
      'مخزن الكرادة',
    ];
  }

  Future<PurchaseModel> createPurchase(
      PurchaseModel purchase,
      ) async {
    await Future.delayed(
      const Duration(milliseconds: 500),
    );

    return purchase;
  }
}
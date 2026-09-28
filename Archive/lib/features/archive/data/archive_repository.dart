import '../../../core/database/app_database.dart';
import '../../purchases/data/purchases_local_repository.dart';
import '../../sales/data/sales_local_repository.dart';

/// الأرشيف يقرأ فواتير المبيعات والمشتريات المحفوظة محلياً.
///
/// لا يحذف السجلات ولا يعيد ترحيلها. التعديل يبقى في شاشتي
/// المبيعات والمشتريات، والمزامنة تبقى عبر الطابور الحالي.
class ArchiveRepository {
  final SalesLocalRepository salesRepository;
  final PurchasesLocalRepository purchasesRepository;

  ArchiveRepository({
    required this.salesRepository,
    required this.purchasesRepository,
  });

  Future<List<Sale>> sales() {
    return salesRepository.getSales();
  }

  Future<List<Purchase>> purchases() {
    return purchasesRepository.getPurchases();
  }
}

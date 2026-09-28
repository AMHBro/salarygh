import '../../products/data/mock_products_repository.dart';
import '../../products/models/product_model.dart';
import '../models/sale_model.dart';

class MockSalesRepository {
  MockSalesRepository();

  /// المبيعات المحفوظة مؤقتاً بالذاكرة.
  /// لاحقاً راح نستبدلها بـ SQLite / Drift.
  static final List<SaleModel> _sales = [];

  /// قائمة الزبائن المؤقتة لشاشة المبيعات.
  ///
  /// لاحقاً راح نربطها مباشرة بجدول Customers
  /// الموجود في قاعدة البيانات المحلية.
  static const List<String> _customers = [
    'زبون نقدي',
    'أحمد محمد',
    'علي حسن',
    'شركة النور',
    'مؤسسة بغداد',
    'محمد كريم',
  ];

  List<ProductModel> getProducts() {
    return List<ProductModel>.from(
      MockProductsRepository.products,
    );
  }

  List<String> getCustomers() {
    return List<String>.from(
      _customers,
    );
  }

  List<SaleModel> getSales() {
    return List<SaleModel>.from(
      _sales,
    );
  }

  ProductModel? getProductById(
      String id,
      ) {
    try {
      return MockProductsRepository.products.firstWhere(
            (product) => product.id == id,
      );
    } catch (_) {
      return null;
    }
  }

  ProductModel? getProductByBarcode(
      String barcode,
      ) {
    final cleanBarcode = barcode.trim();

    if (cleanBarcode.isEmpty) {
      return null;
    }

    try {
      return MockProductsRepository.products.firstWhere(
            (product) =>
        product.barcode == cleanBarcode,
      );
    } catch (_) {
      return null;
    }
  }

  List<ProductModel> searchProducts(
      String query,
      ) {
    final value = query.trim().toLowerCase();

    if (value.isEmpty) {
      return getProducts();
    }

    return MockProductsRepository.products.where(
          (product) {
        return product.name
            .toLowerCase()
            .contains(value) ||
            product.barcode
                .toLowerCase()
                .contains(value) ||
            (product.sku ?? '')
                .toLowerCase()
                .contains(value) ||
            product.categoryName
                .toLowerCase()
                .contains(value);
      },
    ).toList();
  }

  List<ProductModel> getAvailableProducts() {
    return MockProductsRepository.products.where(
          (product) {
        return product.isActive &&
            product.quantity > 0;
      },
    ).toList();
  }

  Future<void> createSale(
      SaleModel sale,
      ) async {
    if (sale.items.isEmpty) {
      throw StateError(
        'لا يمكن إنشاء فاتورة بدون منتجات.',
      );
    }

    if (sale.total < 0) {
      throw StateError(
        'إجمالي الفاتورة غير صحيح.',
      );
    }

    /// تحقق من توفر الكميات قبل الحفظ.
    for (final item in sale.items) {
      final productIndex =
      MockProductsRepository.products.indexWhere(
            (product) =>
        product.id == item.product.id,
      );

      if (productIndex < 0) {
        throw StateError(
          'المنتج "${item.product.name}" غير موجود.',
        );
      }

      final product =
      MockProductsRepository.products[
      productIndex];

      if (!product.isActive) {
        throw StateError(
          'المنتج "${product.name}" غير فعال.',
        );
      }

      if (item.quantity >
          product.quantity) {
        throw StateError(
          'الكمية المطلوبة من "${product.name}" '
              'أكبر من الكمية المتوفرة.',
        );
      }
    }

    /// خصم الكميات من المخزون المؤقت.
    ///
    /// هذا فقط حتى تبقى شاشة المبيعات القديمة تعمل.
    /// لاحقاً الخصم راح يصير عن طريق Stock Movements.
    for (final item in sale.items) {
      final productIndex =
      MockProductsRepository.products.indexWhere(
            (product) =>
        product.id == item.product.id,
      );

      if (productIndex < 0) {
        continue;
      }

      final product =
      MockProductsRepository.products[
      productIndex];

      final newQuantity =
          product.quantity -
              item.quantity;

      MockProductsRepository.products[
      productIndex] = product.copyWith(
        quantity: newQuantity,
      );
    }

    _sales.add(sale);

    /// نخليها Future حتى تبقى واجهة الـRepository
    /// قريبة من النسخة النهائية.
    await Future<void>.delayed(
      const Duration(
        milliseconds: 150,
      ),
    );
  }

  SaleModel? getSaleById(
      int id,
      ) {
    try {
      return _sales.firstWhere(
            (sale) => sale.id == id,
      );
    } catch (_) {
      return null;
    }
  }

  SaleModel? getSaleByInvoiceNumber(
      String invoiceNumber,
      ) {
    final value =
    invoiceNumber.trim();

    if (value.isEmpty) {
      return null;
    }

    try {
      return _sales.firstWhere(
            (sale) =>
        sale.invoiceNumber == value,
      );
    } catch (_) {
      return null;
    }
  }

  void clearSales() {
    _sales.clear();
  }
}
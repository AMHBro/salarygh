import '../models/product_model.dart';

class MockProductsRepository {
  static final List<ProductModel> products = [
    const ProductModel(
      id: '1',
      barcode: '625100000001',
      sku: 'PRD-001',
      name: 'شامبو شعر',
      category: 'العناية الشخصية',
      warehouse: 'المخزن الرئيسي',
      quantity: 120,
      unit: 'قطعة',
      costPrice: 3500,
      repPrice: 4000,
      wholesalePrice: 4500,
      retailPrice: 5000,
      minimumStock: 10,
      isActive: true,
    ),

    const ProductModel(
      id: '2',
      barcode: '625100000002',
      sku: 'PRD-002',
      name: 'معجون أسنان',
      category: 'العناية الشخصية',
      warehouse: 'المخزن الرئيسي',
      quantity: 85,
      unit: 'قطعة',
      costPrice: 2000,
      repPrice: 2500,
      wholesalePrice: 2750,
      retailPrice: 3000,
      minimumStock: 10,
      isActive: true,
    ),

    const ProductModel(
      id: '3',
      barcode: '625100000003',
      sku: 'PRD-003',
      name: 'مناديل ورقية',
      category: 'مواد منزلية',
      warehouse: 'مخزن المنصور',
      quantity: 64,
      unit: 'باكيت',
      costPrice: 1500,
      repPrice: 1750,
      wholesalePrice: 2000,
      retailPrice: 2250,
      minimumStock: 12,
      isActive: true,
    ),

    const ProductModel(
      id: '4',
      barcode: '625100000004',
      sku: 'PRD-004',
      name: 'سائل تنظيف',
      category: 'مواد تنظيف',
      warehouse: 'مخزن الكرادة',
      quantity: 42,
      unit: 'عبوة',
      costPrice: 3000,
      repPrice: 3500,
      wholesalePrice: 3750,
      retailPrice: 4000,
      minimumStock: 8,
      isActive: true,
    ),

    const ProductModel(
      id: '5',
      barcode: '625100000005',
      sku: 'PRD-005',
      name: 'مسحوق غسيل',
      category: 'مواد تنظيف',
      warehouse: 'المخزن الرئيسي',
      quantity: 18,
      unit: 'كيس',
      costPrice: 7000,
      repPrice: 7750,
      wholesalePrice: 8250,
      retailPrice: 9000,
      minimumStock: 10,
      isActive: true,
    ),

    const ProductModel(
      id: '6',
      barcode: '625100000006',
      sku: 'PRD-006',
      name: 'صابون',
      category: 'العناية الشخصية',
      warehouse: 'مخزن المنصور',
      quantity: 5,
      unit: 'قطعة',
      costPrice: 1000,
      repPrice: 1250,
      wholesalePrice: 1500,
      retailPrice: 1750,
      minimumStock: 10,
      isActive: true,
    ),
  ];

  Future<List<ProductModel>>
  getProducts() async {
    await Future<void>.delayed(
      const Duration(
        milliseconds: 100,
      ),
    );

    return List<ProductModel>.from(
      products,
    );
  }

  Future<ProductModel?> getById(
      String id,
      ) async {
    try {
      return products.firstWhere(
            (product) =>
        product.id == id,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ProductModel?>
  getByBarcode(
      String barcode,
      ) async {
    final cleanBarcode =
    barcode.trim();

    try {
      return products.firstWhere(
            (product) =>
        product.barcode ==
            cleanBarcode,
      );
    } catch (_) {
      return null;
    }
  }
}
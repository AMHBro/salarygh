import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_system/core/database/app_database.dart';
import 'package:sales_system/core/money/fx_books.dart';
import 'package:sales_system/core/money/fx_math.dart';
import 'package:sales_system/core/sync/sync_queue_repository.dart';
import 'package:sales_system/features/customers/data/customers_local_repository.dart';
import 'package:sales_system/features/products/models/product_model.dart';
import 'package:sales_system/features/purchases/data/purchases_local_repository.dart';
import 'package:sales_system/features/purchases/models/purchase_model.dart';
import 'package:sales_system/features/reports/data/local_statements_repository.dart';
import 'package:sales_system/features/sales/data/sales_local_repository.dart';
import 'package:sales_system/features/sales/models/cart_item_model.dart';
import 'package:sales_system/features/sales/models/sale_model.dart';
import 'package:sales_system/features/staff/data/staff_ledger.dart';
import 'package:sales_system/features/suppliers/data/suppliers_local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(storage, (call) async => null);

  test('شراء دولار ثم بيع ثم سداد بسعر أعلى يبقي الربح ويفصل فرق الصرف', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final queue = SyncQueueRepository(database: database);
    final purchases = PurchasesLocalRepository(
      database: database,
      syncQueue: queue,
    );
    final sales = SalesLocalRepository(database: database, syncQueue: queue);
    final suppliers = SuppliersLocalRepository(
      database: database,
      syncQueue: queue,
    );
    final statements = LocalStatementsRepository(
      customersRepository: CustomersLocalRepository(
        database: database,
        syncQueue: queue,
      ),
      salesRepository: sales,
      database: database,
    );
    final now = DateTime.now();

    await database.into(database.suppliers).insert(
          SuppliersCompanion.insert(
            id: 'supplier-1',
            name: 'شركة الشاي',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.units).insert(
          UnitsCompanion.insert(
            id: 'piece',
            nameAr: 'قطعة',
            symbol: 'قطعة',
            isBaseUnit: const Value(true),
          ),
        );
    await database.into(database.warehouses).insert(
          WarehousesCompanion.insert(
            id: 'warehouse-1',
            name: 'المخزن',
            status: const Value('ACTIVE'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'product-1',
            name: 'شاي',
            baseUnitId: const Value('piece'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: 'variant-1',
            productId: 'product-1',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await purchases.createPurchase(
      supplierId: 'supplier-1',
      warehouseId: 'warehouse-1',
      discount: 0,
      paymentType: PurchasePaymentType.credit,
      currency: 'USD',
      exchangeRate: 1500,
      items: const [
        PurchaseItemModel(
          productId: 'product-1',
          variantId: 'variant-1',
          unitId: 'piece',
          productName: 'شاي',
          barcode: '',
          quantity: 10,
          unitCost: 1,
        ),
      ],
    );

    final stock = await FxBooks(database).stockValuation(moneyMinor(1700));
    final tea = stock.singleWhere((row) => row['material_name'] == 'شاي');
    expect(tea['quantity'], 10);
    expect(tea['book_value_iqd'], 15000);
    expect(tea['replacement_value_iqd'], 17000);
    expect(tea['fx_effect_iqd'], 2000);

    await sales.createSale(
      warehouseId: 'warehouse-1',
      warehouseName: 'المخزن',
      customerName: 'زبون نقدي',
      items: [
        CartItemModel(
          product: ProductModel(
            id: 'product-1',
            name: 'شاي',
            barcode: '',
            baseUnitId: 'piece',
            costPrice: 1500,
            wholesalePrice: 1800,
            retailPrice: 1800,
          ),
          variantId: 'variant-1',
          unitId: 'piece',
          quantity: 9,
          priceType: PriceType.retail,
          unitPriceOverride: 1800,
        ),
      ],
      subtotal: 16200,
      discount: 0,
      total: 16200,
      paidAmount: 16200,
      remainingAmount: 0,
      paymentType: PaymentType.cash,
    );

    final atPurchaseRate = await _today(
      database,
      moneyMinor(1500),
    );
    expect(atPurchaseRate['sales_total'], 16200);
    expect(atPurchaseRate['cost_total'], 13500);
    expect(atPurchaseRate['profit_total'], 2700);
    expect(atPurchaseRate['replacement_cost'], 13500);
    expect(atPurchaseRate['replacement_profit'], 2700);
    expect(atPurchaseRate['fx_difference'], 0);

    final atNewRate = await _today(database, moneyMinor(1700));
    expect(atNewRate['cost_total'], 13500);
    expect(atNewRate['profit_total'], 2700);
    expect(atNewRate['replacement_cost'], 15300);
    expect(atNewRate['replacement_profit'], 900);

    await purchases.createPurchase(
      supplierId: 'supplier-1',
      warehouseId: 'warehouse-1',
      discount: 0,
      paymentType: PurchasePaymentType.credit,
      currency: 'USD',
      exchangeRate: 1700,
      items: const [
        PurchaseItemModel(
          productId: 'product-1',
          variantId: 'variant-1',
          unitId: 'piece',
          productName: 'شاي',
          barcode: '',
          quantity: 10,
          unitCost: 1,
        ),
      ],
    );

    final afterNewPurchase = await _today(database, moneyMinor(1700));
    expect(afterNewPurchase['cost_total'], 13500);
    expect(afterNewPurchase['profit_total'], 2700);

    await suppliers.registerPayment(
      supplierId: 'supplier-1',
      amount: 10,
      currency: 'USD',
      exchangeRate: 1700,
    );
    await suppliers.registerPayment(
      supplierId: 'supplier-1',
      amount: 10,
      currency: 'USD',
      exchangeRate: 1700,
    );

    final afterPayment = await _today(database, moneyMinor(1700));
    expect(afterPayment['cost_total'], 13500);
    expect(afterPayment['profit_total'], 2700);
    expect(afterPayment['fx_difference'], 2000);
    expect(afterPayment['fx_note'], 'ارتفاع الدولار من 1500 إلى 1700');
    expect(afterPayment['net_total'], 700);

    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'product-2',
            name: 'سكر',
            baseUnitId: const Value('piece'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: 'variant-2',
            productId: 'product-2',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await purchases.createPurchase(
      supplierId: 'supplier-1',
      warehouseId: 'warehouse-1',
      discount: 0,
      paymentType: PurchasePaymentType.credit,
      items: const [
        PurchaseItemModel(
          productId: 'product-2',
          variantId: 'variant-2',
          unitId: 'piece',
          productName: 'سكر',
          barcode: '',
          quantity: 2,
          unitCost: 1000,
        ),
      ],
    );

    final statement = await statements.supplierStatement(
      supplierId: 'supplier-1',
    );
    expect(statement.last['running_balance_usd'], 0);
    expect(statement.last['running_balance_iqd'], 2000);
    final dollarCredits = statement.fold<double>(
      0,
      (sum, row) => sum + (row['credit_usd'] as num).toDouble(),
    );
    final dollarDebits = statement.fold<double>(
      0,
      (sum, row) => sum + (row['debit_usd'] as num).toDouble(),
    );
    expect(dollarCredits, 20);
    expect(dollarDebits, 20);

    final capital = await statements.capitalStatement();
    final saleRow = capital.singleWhere(
      (row) => row['operation_type'] == 'بيع',
    );
    expect(saleRow['cost_iqd'], 13500);
    expect(saleRow['profit_iqd'], 2700);
  });
}

Future<Map<String, dynamic>> _today(AppDatabase database, int rateMillis) async {
  final rows = await StaffLedger(database).dailyProfit(rateMillis: rateMillis);
  return rows.singleWhere((row) => row['day'] != 'المجموع');
}

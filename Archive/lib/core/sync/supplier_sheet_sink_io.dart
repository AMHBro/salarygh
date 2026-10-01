import '../../features/purchases/data/supplier_folder.dart';

Future<void> saveSupplierSheet({
  required String sheetId,
  required String supplierName,
  required String title,
  required String imageUrl,
  required DateTime savedAt,
}) {
  return SupplierFolder.saveDataUrl(
    sheetId: sheetId,
    supplierName: supplierName,
    title: title,
    imageUrl: imageUrl,
    savedAt: savedAt,
  );
}

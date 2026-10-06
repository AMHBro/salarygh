import '../../../core/di/app_services.dart';

Future<Map<String, String>> localProductImages() async {
  final rows = await AppServices.database.customSelect('''
SELECT COALESCE(p.server_id, '') AS server_id,
       COALESCE(p.sku, '') AS sku,
       COALESCE(p.image_url, '') AS image_url,
       COALESCE(l.remote_product_id, '') AS remote_id
FROM products p
LEFT JOIN store_catalog_links l ON l.local_product_id = p.id
WHERE p.image_url IS NOT NULL AND trim(p.image_url) <> ''
''').get();
  final images = <String, String>{};
  for (final row in rows) {
    final image = row.read<String>('image_url').trim();
    if (image.isEmpty) continue;
    final serverId = row.read<String>('server_id').trim();
    final remoteId = row.read<String>('remote_id').trim();
    final sku = row.read<String>('sku').trim();
    if (serverId.isNotEmpty) images[serverId] = image;
    if (remoteId.isNotEmpty) images[remoteId] = image;
    if (sku.isNotEmpty) images['sku:$sku'] = image;
  }
  return images;
}

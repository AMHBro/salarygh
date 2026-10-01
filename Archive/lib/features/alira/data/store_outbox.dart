import 'store_outbox_web.dart'
    if (dart.library.io) 'store_outbox_io.dart' as outbox;

Future<List<Map<String, dynamic>>> readStoreOutbox() => outbox.readStoreOutbox();

Future<void> writeStoreOutbox(List<Map<String, dynamic>> items) =>
    outbox.writeStoreOutbox(items);

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

const _dbName = 'sayler-store';
const _storeName = 'outbox';
const _queueKey = 'queue';
const _fallbackKey = 'sayler.store.outbox';

@JS('indexedDB')
external JSAny? get _indexedDB;

@JS('localStorage')
external _WebStorage get _localStorage;

@JS()
extension type _WebStorage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}

@JS()
extension type _IDBFactory(JSObject _) implements JSObject {
  external _IDBOpenRequest open(JSString name, JSNumber version);
}

@JS()
extension type _IDBOpenRequest(JSObject _) implements JSObject {
  external set onupgradeneeded(JSFunction? value);
  external set onsuccess(JSFunction? value);
  external set onerror(JSFunction? value);
  external JSAny? get result;
}

@JS()
extension type _IDBDatabase(JSObject _) implements JSObject {
  external _DOMStringList get objectStoreNames;
  external void createObjectStore(JSString name);
  external _IDBTransaction transaction(JSString store, JSString mode);
}

@JS()
extension type _DOMStringList(JSObject _) implements JSObject {
  external bool contains(JSString value);
}

@JS()
extension type _IDBTransaction(JSObject _) implements JSObject {
  external _IDBObjectStore objectStore(JSString name);
  external set oncomplete(JSFunction? value);
  external set onerror(JSFunction? value);
}

@JS()
extension type _IDBObjectStore(JSObject _) implements JSObject {
  external _IDBRequest put(JSAny value, JSString key);
  external _IDBRequest get(JSString key);
}

@JS()
extension type _IDBRequest(JSObject _) implements JSObject {
  external set onsuccess(JSFunction? value);
  external set onerror(JSFunction? value);
  external JSAny? get result;
}

Future<List<Map<String, dynamic>>> readStoreOutbox() async {
  try {
    final raw = await _idbGet();
    if (raw != null) return _decode(raw);
  } catch (_) {}
  return _decode(_localStorage.getItem(_fallbackKey.toJS)?.toDart);
}

Future<void> writeStoreOutbox(List<Map<String, dynamic>> items) async {
  final encoded = jsonEncode(items);
  Object? storageError;
  try {
    _localStorage.setItem(_fallbackKey.toJS, encoded.toJS);
  } catch (error) {
    storageError = error;
  }
  try {
    await _idbPut(encoded);
  } catch (error) {
    if (storageError != null) throw error;
  }
}

List<Map<String, dynamic>> _decode(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  final parsed = jsonDecode(raw);
  if (parsed is! List) return [];
  return [
    for (final item in parsed)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Future<_IDBDatabase> _open() {
  final factory = _indexedDB;
  if (factory == null) {
    return Future.error(StateError('indexedDB'));
  }
  final completer = Completer<_IDBDatabase>();
  final request = _IDBFactory(factory as JSObject).open(_dbName.toJS, 1.toJS);
  request.onupgradeneeded = ((JSAny? _) {
    final database = _IDBDatabase(request.result! as JSObject);
    if (!database.objectStoreNames.contains(_storeName.toJS)) {
      database.createObjectStore(_storeName.toJS);
    }
  }).toJS;
  request.onsuccess = ((JSAny? _) {
    if (!completer.isCompleted) {
      completer.complete(_IDBDatabase(request.result! as JSObject));
    }
  }).toJS;
  request.onerror = ((JSAny? _) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('indexedDB'));
    }
  }).toJS;
  return completer.future;
}

Future<String?> _idbGet() async {
  final database = await _open();
  final completer = Completer<String?>();
  final transaction = database.transaction(_storeName.toJS, 'readonly'.toJS);
  final request = transaction.objectStore(_storeName.toJS).get(_queueKey.toJS);
  request.onsuccess = ((JSAny? _) {
    final value = request.result?.dartify();
    if (!completer.isCompleted) {
      completer.complete(value?.toString());
    }
  }).toJS;
  request.onerror = ((JSAny? _) {
    if (!completer.isCompleted) completer.completeError(StateError('indexedDB'));
  }).toJS;
  return completer.future;
}

Future<void> _idbPut(String encoded) async {
  final database = await _open();
  final completer = Completer<void>();
  final transaction = database.transaction(_storeName.toJS, 'readwrite'.toJS);
  transaction.oncomplete = ((JSAny? _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  transaction.onerror = ((JSAny? _) {
    if (!completer.isCompleted) completer.completeError(StateError('indexedDB'));
  }).toJS;
  transaction.objectStore(_storeName.toJS).put(encoded.toJS, _queueKey.toJS);
  return completer.future;
}

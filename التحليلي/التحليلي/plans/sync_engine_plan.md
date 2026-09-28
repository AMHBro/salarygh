# 🔄 نظام المزامنة Offline/Online — Sayler Sync Engine

> **الاستراتيجية**: Optimistic Sync + Delta Pull + Conflict Resolution  
> **التاريخ**: أغسطس 2026

---

## 🎯 المتطلبات

- النظام يعمل **بالكامل offline** (بدون إنترنت)
- عند عودة الاتصال تتم **المزامنة التلقائية**
- حل التعارضات بذكاء دون فقدان بيانات
- دعم **أجهزة متعددة** في نفس الوقت

---

## 🏗️ المعمارية العامة

```
┌─────────────────────────────┐
│       Frontend (Client)      │
│                              │
│  ┌─────────────────────┐    │
│  │   Local IndexedDB    │    │
│  │  (Offline Storage)   │    │
│  └──────────┬──────────┘    │
│             │                │
│  ┌──────────▼──────────┐    │
│  │    Sync Queue        │    │
│  │  (Pending Changes)   │    │
│  └──────────┬──────────┘    │
└─────────────┼───────────────┘
              │ HTTP (when online)
              │
┌─────────────▼───────────────┐
│       Backend (NestJS)       │
│                              │
│  ┌─────────────────────┐    │
│  │   Sync Controller    │    │
│  │  POST /sync/push     │    │
│  │  GET  /sync/pull     │    │
│  └──────────┬──────────┘    │
│             │                │
│  ┌──────────▼──────────┐    │
│  │   Conflict Resolver  │    │
│  └──────────┬──────────┘    │
│             │                │
│  ┌──────────▼──────────┐    │
│  │     PostgreSQL       │    │
│  └─────────────────────┘    │
└─────────────────────────────┘
```

---

## 📡 API Endpoints للـ Sync

### `POST /sync/push`
يرسل التغييرات المحلية إلى الخادم
```typescript
// Request Body
{
  device_id: string,
  changes: [
    {
      entity_type: 'sales_invoices' | 'customers' | ...,
      entity_id: string,
      operation: 'CREATE' | 'UPDATE' | 'DELETE',
      payload: object,
      client_version: number,
      client_timestamp: string
    }
  ]
}

// Response
{
  accepted: string[],       // entity_ids تم قبولها
  rejected: [               // entity_ids تم رفضها مع السبب
    { entity_id, reason, server_data }
  ],
  conflicts: [              // حالات تعارض
    { entity_id, resolution, final_data }
  ]
}
```

### `GET /sync/pull?last_seq=<number>&entities=<list>`
يجلب التغييرات التي فاتت العميل
```typescript
// Response
{
  changes: [
    {
      entity_type: string,
      entity_id: string,
      operation: string,
      data: object,
      server_seq: number,
      server_timestamp: string
    }
  ],
  current_seq: number,
  has_more: boolean
}
```

### `GET /sync/status`
حالة المزامنة للجهاز الحالي
```typescript
{
  device_id: string,
  last_sync: string,
  pending_changes: number,
  server_seq: number
}
```

---

## ⚔️ قواعد حل التعارض (Conflict Resolution)

### قاعدة 1: المبيعات المؤكدة — لا تُلغى
```
if (server.invoice.status === 'PAID') {
  // رفض أي تعديل من العميل
  // إرجاع الـ server_data للعميل ليحدّث نسخته
}
```

### قاعدة 2: المخزون — يُجمع لا يُستبدل
```
// العميل ينقص 5 من المخزون أثناء الـ offline
// الخادم أيضاً أنقص 3
// النتيجة: نُنقص 8 (ليس استبدال بقيمة واحدة)
server.stock = server.stock - client.delta
```

### قاعدة 3: إعدادات المستخدم — Last Write Wins
```
if (client.updated_at > server.updated_at) {
  // العميل أحدث → اقبل تغيير العميل
} else {
  // الخادم أحدث → أبلغ العميل ليحدّث نسخته
}
```

### قاعدة 4: إنشاء فاتورة مكررة — Idempotency Key
```
if (invoice.idempotency_key exists in DB) {
  // لا تنشئ فاتورة جديدة
  // أرجع الفاتورة الموجودة للعميل
  return existing_invoice;
}
```

---

## 🔢 نظام الـ Versioning

كل سجل يحتوي على:
```sql
version INT DEFAULT 1
-- يزيد 1 في كل تعديل على الخادم
```

العميل يرسل `client_version` مع كل تعديل:
- إذا `client_version == server.version` → تعارض محتمل
- إذا `client_version < server.version` → الخادم أحدث، تطبيق قواعد الحل
- إذا `client_version == server.version - 1` → تعديل متسلسل صحيح

---

## 📋 الكيانات الداعمة للـ Offline

| الكيان | يدعم Offline؟ | ملاحظة |
|--------|--------------|--------|
| `sales_invoices` | ✅ نعم | مع idempotency_key |
| `sales_invoice_items` | ✅ نعم | مع الفاتورة |
| `customers` | ✅ نعم | إنشاء وتعديل |
| `products` | ⬇️ قراءة فقط | يُحمَّل مسبقاً |
| `stock_levels` | ⬇️ قراءة فقط | يُحدَّث عبر الـ sync |
| `payments` | ✅ نعم | مع idempotency_key |
| `warehouse_transfers` | ✅ نعم | محدود |
| `reports` | ❌ لا | تحتاج الخادم |
| `settings` | ⬇️ قراءة فقط | |

---

## 🔧 تطبيق الـ Backend (NestJS)

### `sync.module.ts`
```typescript
@Module({
  imports: [
    TypeOrmModule.forFeature([SyncLog, DeviceSyncState]),
    BullModule.registerQueue({ name: 'sync' }),
  ],
  controllers: [SyncController],
  providers: [SyncService, ConflictResolverService],
  exports: [SyncService],
})
export class SyncModule {}
```

### `sync.service.ts` (المنطق الأساسي)
```typescript
@Injectable()
export class SyncService {
  
  async push(deviceId: string, changes: SyncChange[]) {
    const results = { accepted: [], rejected: [], conflicts: [] };
    
    for (const change of changes) {
      await this.dataSource.transaction(async (em) => {
        const result = await this.processChange(em, deviceId, change);
        results[result.status].push(result);
      });
    }
    
    return results;
  }
  
  async pull(deviceId: string, lastSeq: number) {
    return this.syncLogRepo.find({
      where: { serverSeq: MoreThan(lastSeq) },
      order: { serverSeq: 'ASC' },
      take: 500,
    });
  }
  
  private async processChange(em, deviceId, change) {
    const resolver = this.conflictResolver.getResolver(change.entityType);
    return resolver.resolve(em, change);
  }
}
```

---

## 📱 ما يحتاجه الـ Frontend (شريكك)

وضّح لشريكك هذه النقاط:

1. **IndexedDB**: استخدم `Dexie.js` أو `PouchDB` للتخزين المحلي
2. **Sync Queue**: كل عملية تُضاف للـ Queue أولاً، ثم تُرسل
3. **Online Detection**: `navigator.onLine` + `window.addEventListener('online')`
4. **Idempotency Key**: أنشئه في الـ frontend قبل الإرسال (`UUID v4`)
5. **Conflict UI**: عند وجود conflict، اعرض للمستخدم خياراً إذا لزم

### مثال على Sync Queue في Frontend:
```typescript
// كل عملية تُسجَّل هكذا
const pendingChange = {
  id: uuid(),
  entity_type: 'sales_invoices',
  entity_id: invoice.id,
  operation: 'CREATE',
  payload: invoice,
  idempotency_key: uuid(),  // مهم جداً!
  created_at: new Date().toISOString()
};

// حفظ في IndexedDB
await db.syncQueue.add(pendingChange);

// عند الاتصال
if (navigator.onLine) {
  await syncService.push(pendingChanges);
}
```

---

## ⚙️ إعدادات المزامنة

```env
# مدة الـ Sync
SYNC_INTERVAL_SECONDS=30        # كل 30 ثانية عند الاتصال
SYNC_BATCH_SIZE=100             # عدد التغييرات في كل batch
SYNC_MAX_RETRY=3                # عدد محاولات إعادة الإرسال
SYNC_CONFLICT_WINDOW_SECONDS=300 # نافزة حل التعارض (5 دقائق)
```

---

> **ملاحظة**: هذه الوثيقة للتنسيق بين Backend وFrontend.  
> يجب الاتفاق على صيغة الـ API النهائية قبل التطوير.

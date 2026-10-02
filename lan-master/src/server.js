/**
 * خادم الحاسبة الأساسية.
 * يفتح sayler.sqlite على القرص المحلي فقط، ويرتّب عمليات الحاسبات الفرعية.
 * الحاسبات الأخرى لا تحصل على مسار الملف.
 */
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

const token = (process.env.LAN_TOKEN || '').trim();
if (!token) {
  console.error('LAN_TOKEN مطلوب قبل تشغيل خادم الشبكة. لا يُطبع الرمز.');
  process.exit(1);
}

const port = Number(process.env.LAN_PORT || 3920);
const sqlitePath = path.resolve(
  process.env.SAYLER_SQLITE ||
    path.join(os.homedir(), 'Documents', 'sayler.sqlite'),
);

if (sqlitePath.startsWith('\\\\') || sqlitePath.startsWith('//')) {
  console.error('مسار القاعدة يجب أن يكون على قرص الحاسبة الأساسية، لا على مشاركة شبكة.');
  process.exit(1);
}

const db = new DatabaseSync(sqlitePath);
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA busy_timeout = 8000');
db.exec(`
  CREATE TABLE IF NOT EXISTS lan_inbox (
    id TEXT PRIMARY KEY,
    idempotency_key TEXT NOT NULL UNIQUE,
    kind TEXT NOT NULL,
    payload TEXT NOT NULL,
    status TEXT NOT NULL,
    error TEXT,
    result_json TEXT,
    created_at TEXT NOT NULL
  )
`);

const insertInbox = db.prepare(`
  INSERT INTO lan_inbox (
    id, idempotency_key, kind, payload, status, created_at
  ) VALUES (?, ?, ?, ?, 'pending', ?)
  ON CONFLICT(idempotency_key) DO NOTHING
`);
const findByKey = db.prepare(`
  SELECT id, idempotency_key, kind, status, error, result_json, created_at
  FROM lan_inbox WHERE idempotency_key = ?
`);
const findById = db.prepare(`
  SELECT id, idempotency_key, kind, status, error, result_json, created_at
  FROM lan_inbox WHERE id = ?
`);

function send(res, status, body) {
  const raw = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(raw),
  });
  res.end(raw);
}

function authorized(req) {
  const header = String(req.headers.authorization || '');
  return header === `Bearer ${token}`;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 1_000_000) {
        reject(new Error('الجسم أكبر من الحد'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (!chunks.length) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch (error) {
        reject(error);
      }
    });
    req.on('error', reject);
  });
}

function queueRow(row) {
  return {
    id: row.id,
    idempotencyKey: row.idempotency_key,
    kind: row.kind,
    status: row.status,
    error: row.error,
    result: row.result_json ? JSON.parse(row.result_json) : null,
    createdAt: row.created_at,
  };
}

function readStock(url) {
  const warehouseId = url.searchParams.get('warehouseId') || '';
  if (!warehouseId) {
    return db.prepare(`
      SELECT variant_id, warehouse_id, quantity
      FROM stock_balances
      LIMIT 2000
    `).all();
  }
  return db.prepare(`
    SELECT variant_id, warehouse_id, quantity
    FROM stock_balances
    WHERE warehouse_id = ?
    LIMIT 2000
  `).all(warehouseId);
}

function readCustomers(url) {
  const q = `%${url.searchParams.get('q') || ''}%`;
  return db.prepare(`
    SELECT id, name, phone, credit_limit, is_active
    FROM customers
    WHERE deleted_at IS NULL AND name LIKE ?
    ORDER BY name
    LIMIT 40
  `).all(q);
}

function readProducts(url) {
  const q = `%${url.searchParams.get('q') || ''}%`;
  return db.prepare(`
    SELECT id, name, barcode, retail_price, wholesale_price
    FROM products
    WHERE deleted_at IS NULL AND name LIKE ?
    ORDER BY name
    LIMIT 500
  `).all(q);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || '/', 'http://127.0.0.1');
    if (req.method === 'GET' && url.pathname === '/health') {
      send(res, 200, { ok: true, role: 'master' });
      return;
    }
    if (!authorized(req)) {
      send(res, 401, { message: 'رمز الشبكة المحلية غير صحيح' });
      return;
    }
    if (req.method === 'GET' && url.pathname === '/v1/reads/stock') {
      send(res, 200, { data: readStock(url) });
      return;
    }
    if (req.method === 'GET' && url.pathname === '/v1/reads/customers') {
      send(res, 200, { data: readCustomers(url) });
      return;
    }
    if (req.method === 'GET' && url.pathname === '/v1/reads/products') {
      send(res, 200, { data: readProducts(url) });
      return;
    }
    if (req.method === 'GET' && url.pathname.startsWith('/v1/queue/')) {
      const id = decodeURIComponent(url.pathname.slice('/v1/queue/'.length));
      const row = findById.get(id);
      if (!row) {
        send(res, 404, { message: 'العملية غير موجودة' });
        return;
      }
      send(res, 200, queueRow(row));
      return;
    }
    if (req.method === 'POST' && url.pathname === '/v1/queue') {
      const body = await readBody(req);
      const idempotencyKey = String(body.idempotencyKey || '').trim();
      const kind = String(body.kind || '').trim();
      if (!idempotencyKey || !kind || body.payload == null) {
        send(res, 400, { message: 'المفتاح ونوع العملية والحمولة مطلوبة' });
        return;
      }
      const id = idempotencyKey;
      insertInbox.run(
        id,
        idempotencyKey,
        kind,
        JSON.stringify(body.payload),
        new Date().toISOString(),
      );
      const row = findByKey.get(idempotencyKey);
      send(res, 202, queueRow(row));
      return;
    }
    send(res, 404, { message: 'المسار غير موجود' });
  } catch (error) {
    send(res, 500, { message: error instanceof Error ? error.message : 'تعذر تنفيذ الطلب' });
  }
});

server.listen(port, '0.0.0.0', () => {
  console.log(`LAN master listening on 0.0.0.0:${port}`);
});

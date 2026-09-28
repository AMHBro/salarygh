const base = 'http://127.0.0.1:3000/api/v1';

function rows(payload) {
  if (!payload) return [];
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload.data)) return payload.data;
  if (payload.data && Array.isArray(payload.data.items)) return payload.data.items;
  if (payload.data && Array.isArray(payload.data.data)) return payload.data.data;
  if (Array.isArray(payload.items)) return payload.items;
  return [];
}

async function api(token, method, path, body) {
  const response = await fetch(base + path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: 'Bearer ' + token } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  if (!response.ok) {
    throw new Error(method + ' ' + path + ' ' + response.status + ' ' + text.slice(0, 600));
  }
  return json;
}

function variantId(product) {
  return (
    product.product_variants?.[0]?.id ||
    product.variants?.[0]?.id ||
    product.variant?.id ||
    null
  );
}

async function ensureCashbox(branchId) {
  const { PrismaClient } = await import(
    '../syler-backend-main/syler-backend-main/node_modules/@prisma/client/index.js'
  );
  const prisma = new PrismaClient();
  try {
    const existing = await prisma.cashboxes.findFirst({
      where: { branch_id: branchId },
    });
    if (existing) return existing.id;
    const created = await prisma.cashboxes.create({
      data: {
        device_code: 'POS-DEMO',
        cashbox_code: 'CASH-DEMO',
        name: 'صندوق التجربة',
        branch_id: branchId,
        status: 'OPEN',
      },
    });
    return created.id;
  } finally {
    await prisma.$disconnect();
  }
}

async function main() {
  const login = await api(null, 'POST', '/auth/login', {
    email: 'admin@sayler.app',
    password: 'Admin@123456',
  });
  const token = login.accessToken;
  if (!token) throw new Error('تعذر تسجيل الدخول');

  const created = [];
  const warehouses = rows(await api(token, 'GET', '/warehouses'));
  const warehouse = warehouses.find(
    (item) => String(item.status || '').toUpperCase() === 'ACTIVE',
  );
  if (!warehouse) throw new Error('لا يوجد مخزن فعال');

  const units = rows(await api(token, 'GET', '/units'));
  const piece = units.find((item) => item.name_ar === 'قطعة') || units[0];
  if (!piece) throw new Error('لا توجد وحدة قياس');

  const products = rows(await api(token, 'GET', '/products?page=1&limit=100'));
  const byName = {};
  for (const product of products) {
    let id = variantId(product);
    if (!id && product.id) {
      const detail = await api(token, 'GET', '/products/' + product.id);
      const full = detail.data || detail;
      id = variantId(full);
    }
    byName[product.name_ar] = { ...product, variant_id: id };
  }

  function item(name, quantity, priceField) {
    const product = byName[name];
    if (!product?.variant_id) {
      throw new Error('المنتج غير موجود: ' + name);
    }
    const prices = {
      retail: {
        'رز بسمتي': 25000,
        'زيت طبخ 1 لتر': 3200,
        'سكر 1 كغم': 1500,
        'ماء 1.5 لتر': 500,
        'عصير برتقال': 1200,
        'صابون سائل': 2500,
        'مسحوق غسيل': 6000,
      },
      wholesale: {
        'رز بسمتي': 22000,
        'زيت طبخ 1 لتر': 2800,
        'سكر 1 كغم': 1300,
        'ماء 1.5 لتر': 350,
        'عصير برتقال': 950,
        'صابون سائل': 2000,
        'مسحوق غسيل': 5000,
      },
      cost: {
        'رز بسمتي': 18000,
        'زيت طبخ 1 لتر': 2200,
        'سكر 1 كغم': 900,
        'ماء 1.5 لتر': 250,
        'عصير برتقال': 700,
        'صابون سائل': 1500,
        'مسحوق غسيل': 4000,
      },
    };
    return {
      variant_id: product.variant_id,
      unit_id: piece.id,
      quantity,
      unit_price: prices[priceField][name],
      unit_cost: prices.cost[name],
    };
  }

  const customers = rows(await api(token, 'GET', '/customers?page=1&limit=100'));
  const customer = (name) => customers.find((item) => item.name === name);
  const suppliers = rows(await api(token, 'GET', '/suppliers?page=1&limit=100'));
  const supplier = suppliers.find((item) => item.name === 'شركة النور للتجارة');
  if (!supplier) throw new Error('شركة النور غير موجودة');

  const existingSales = rows(await api(token, 'GET', '/direct-sales?page=1&limit=100'));
  const existingPurchases = rows(await api(token, 'GET', '/purchases?page=1&limit=100'));
  const saleNotes = new Set(existingSales.map((item) => item.notes || ''));
  const purchaseNotes = new Set(existingPurchases.map((item) => item.notes || ''));

  async function sale(note, body) {
    if ([...saleNotes].some((value) => value.includes(note))) {
      created.push('موجود: ' + note);
      return null;
    }
    const result = await api(token, 'POST', '/direct-sales', {
      warehouse_id: warehouse.id,
      discount_amount: 0,
      notes: note,
      ...body,
    });
    created.push(note);
    return result.data || result;
  }

  async function purchase(note, body) {
    if ([...purchaseNotes].some((value) => value.includes(note))) {
      created.push('موجود: ' + note);
      return null;
    }
    const result = await api(token, 'POST', '/purchases', {
      supplier_id: supplier.id,
      warehouse_id: warehouse.id,
      discount_amount: 0,
      notes: note,
      ...body,
    });
    created.push(note);
    return result.data || result;
  }

  const riceBuy = item('رز بسمتي', 10, 'cost');
  const oilBuy = item('زيت طبخ 1 لتر', 20, 'cost');
  const sugarBuy = item('سكر 1 كغم', 15, 'cost');

  await purchase('تجريبي: شراء نقدي', {
    payment_type: 'CASH',
    items: [
      {
        variant_id: riceBuy.variant_id,
        unit_id: piece.id,
        quantity: 10,
        unit_cost: riceBuy.unit_cost,
      },
    ],
  });

  const creditPurchase = await purchase('تجريبي: شراء آجل', {
    payment_type: 'CREDIT',
    items: [
      {
        variant_id: oilBuy.variant_id,
        unit_id: piece.id,
        quantity: 20,
        unit_cost: oilBuy.unit_cost,
      },
    ],
  });

  const sugarPurchase = await purchase('تجريبي: شراء جزئي', {
    payment_type: 'PARTIAL',
    paid_amount: 5000,
    items: [
      {
        variant_id: sugarBuy.variant_id,
        unit_id: piece.id,
        quantity: 15,
        unit_cost: sugarBuy.unit_cost,
      },
    ],
  });

  const water = item('ماء 1.5 لتر', 10, 'retail');
  const juice = item('عصير برتقال', 2, 'retail');
  const rice = item('رز بسمتي', 2, 'retail');
  const oil = item('زيت طبخ 1 لتر', 3, 'retail');
  const sugar = item('سكر 1 كغم', 5, 'retail');
  const soap = item('صابون سائل', 2, 'retail');
  const powder = item('مسحوق غسيل', 4, 'wholesale');
  const riceWholesale = item('رز بسمتي', 1, 'wholesale');

  function line(entry) {
    return {
      variant_id: entry.variant_id,
      unit_id: piece.id,
      quantity: entry.quantity,
      unit_price: entry.unit_price,
    };
  }

  await sale('تجريبي: بيع نقدي', {
    price_type: 'RETAIL',
    payment_type: 'CASH',
    items: [line(water), line(juice)],
  });

  const creditSale = await sale('تجريبي: بيع آجل', {
    customer_id: customer('علي حسن')?.id,
    price_type: 'RETAIL',
    payment_type: 'CREDIT',
    items: [line(rice), line(oil)],
  });

  await sale('تجريبي: بيع جزئي', {
    customer_id: customer('سارة كريم')?.id,
    price_type: 'RETAIL',
    payment_type: 'PARTIAL',
    paid_amount: 5000,
    items: [line(sugar), line(soap)],
  });

  await sale('تجريبي: بيع جملة', {
    customer_id: customer('محل الأمين')?.id,
    price_type: 'WHOLESALE',
    payment_type: 'CASH',
    items: [line(powder), line(riceWholesale)],
  });

  const cashboxId = await ensureCashbox(warehouse.branch_id || warehouse.branch?.id);
  const ali = customer('علي حسن');
  const creditInvoiceId =
    creditSale?.invoice?.id || creditSale?.id || creditSale?.invoice_id;
  if (ali && creditInvoiceId) {
    await api(token, 'POST', '/customers/' + ali.id + '/payments', {
      amount: 20000,
      idempotency_key: crypto.randomUUID(),
      cashbox_id: cashboxId,
      invoice_id: creditInvoiceId,
      notes: 'تجريبي: قبض من علي حسن',
    });
    created.push('تجريبي: قبض من علي حسن');
  }

  const purchaseInvoiceId =
    creditPurchase?.id || creditPurchase?.invoice?.id || sugarPurchase?.id;
  if (purchaseInvoiceId) {
    await api(token, 'POST', '/supplier-payments', {
      supplier_id: supplier.id,
      invoice_id: purchaseInvoiceId,
      amount: 10000,
      idempotency_key: crypto.randomUUID(),
      payment_method: 'CASH',
      cashbox_id: cashboxId,
      notes: 'تجريبي: دفع لشركة النور',
    });
    created.push('تجريبي: دفع لشركة النور');
  }

  console.log(created.join('\n'));
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});

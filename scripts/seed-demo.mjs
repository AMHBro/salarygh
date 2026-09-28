const base = 'http://127.0.0.1:3000/api/v1';

async function activateWarehouse(id) {
  const { PrismaClient } = await import(
    '../syler-backend-main/syler-backend-main/node_modules/@prisma/client/index.js'
  );
  const prisma = new PrismaClient();
  try {
    await prisma.warehouses.update({
      where: { id },
      data: { status: 'ACTIVE' },
    });
  } finally {
    await prisma.$disconnect();
  }
}

async function api(token, method, path, body) {
  const response = await fetch(base + path, {
    method,
    headers: {
      'content-type': 'application/json',
      authorization: 'Bearer ' + token,
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
    throw new Error(
      method + ' ' + path + ' ' + response.status + ' ' + text.slice(0, 500),
    );
  }
  return json;
}

function rows(payload) {
  if (!payload) return [];
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload.data)) return payload.data;
  if (payload.data && Array.isArray(payload.data.items)) return payload.data.items;
  if (payload.data && Array.isArray(payload.data.data)) return payload.data.data;
  if (Array.isArray(payload.items)) return payload.items;
  return [];
}

async function main() {
  const login = await api(null, 'POST', '/auth/login', {
    email: 'admin@sayler.app',
    password: 'Admin@123456',
  }).catch(async () => {
    const response = await fetch(base + '/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        email: 'admin@sayler.app',
        password: 'Admin@123456',
      }),
    });
    return response.json();
  });

  const token = login.accessToken || login.data?.accessToken;
  if (!token) {
    throw new Error('تعذر تسجيل الدخول');
  }

  const created = [];

  const branchPayload = await api(token, 'GET', '/branches');
  const branches = rows(branchPayload);
  const branch =
    branches.find((item) => String(item.status || '').toUpperCase() === 'ACTIVE') ||
    branches[0];
  if (!branch) {
    throw new Error('لا يوجد فرع. فعّل فرعاً أولاً.');
  }

  let warehouses = rows(await api(token, 'GET', '/warehouses'));
  let warehouse = warehouses.find(
    (item) => String(item.status || '').toUpperCase() === 'ACTIVE',
  );

  if (!warehouse) {
    const named = warehouses.find((item) => item.name === 'المخزن الرئيسي');
    if (!named) {
      const made = await api(token, 'POST', '/warehouses', {
        code: 'WH-DEMO',
        name: 'المخزن الرئيسي',
        branch_id: branch.id,
        type: 'MAIN',
        address: 'بغداد - الكرادة',
      });
      warehouse = made.data || made;
      warehouses.push(warehouse);
      created.push('مخزن: المخزن الرئيسي');
    } else {
      warehouse = named;
    }
  }

  if (String(warehouse.status || '').toUpperCase() !== 'ACTIVE') {
    await activateWarehouse(warehouse.id);
    warehouse.status = 'ACTIVE';
    created.push('تم تفعيل المخزن الرئيسي');
  }

  const unitNames = [
    { name_ar: 'قطعة', name_en: 'Piece', symbol: 'PCS', is_base_unit: true },
    { name_ar: 'كارتون', name_en: 'Carton', symbol: 'CTN', is_base_unit: true },
  ];
  let units = rows(await api(token, 'GET', '/units'));
  for (const unit of unitNames) {
    if (units.some((item) => item.name_ar === unit.name_ar)) continue;
    const made = await api(token, 'POST', '/units', unit);
    units.push(made.data || made);
    created.push('وحدة: ' + unit.name_ar);
  }
  const piece = units.find((item) => item.name_ar === 'قطعة') || units[0];

  const categoryNames = ['مواد غذائية', 'مشروبات', 'منظفات'];
  let categories = rows(await api(token, 'GET', '/categories'));
  for (const name of categoryNames) {
    if (categories.some((item) => item.name_ar === name)) continue;
    const made = await api(token, 'POST', '/categories', { name_ar: name });
    categories.push(made.data || made);
    created.push('صنف: ' + name);
  }

  const categoryId = (name) =>
    categories.find((item) => item.name_ar === name)?.id;

  const products = [
    ['رز بسمتي', 'مواد غذائية', '100000000001', 18000, 20000, 22000, 25000, 80],
    ['زيت طبخ 1 لتر', 'مواد غذائية', '100000000002', 2200, 2500, 2800, 3200, 60],
    ['سكر 1 كغم', 'مواد غذائية', '100000000003', 900, 1100, 1300, 1500, 100],
    ['ماء 1.5 لتر', 'مشروبات', '100000000004', 250, 300, 350, 500, 120],
    ['عصير برتقال', 'مشروبات', '100000000005', 700, 850, 950, 1200, 70],
    ['صابون سائل', 'منظفات', '100000000006', 1500, 1800, 2000, 2500, 50],
    ['مسحوق غسيل', 'منظفات', '100000000007', 4000, 4500, 5000, 6000, 40],
  ];

  const existingProducts = rows(
    await api(token, 'GET', '/products?page=1&limit=100'),
  );

  for (const [name, category, barcode, cost, rep, wholesale, retail, qty] of products) {
    let product = existingProducts.find((item) => item.name_ar === name);
    if (!product) {
      const made = await api(token, 'POST', '/products', {
        name_ar: name,
        barcode,
        sku: 'DEMO-' + barcode.slice(-3),
        category_id: categoryId(category),
        base_unit_id: piece.id,
        description: 'بيانات تجريبية',
        min_stock_level: 5,
        has_variants: false,
        pricing: {
          cost_price: cost,
          rep_price: rep,
          wholesale_price: wholesale,
          retail_price: retail,
        },
      });
      product = made.data || made;
      existingProducts.push(product);
      created.push('منتج: ' + name);
    }

    const variantId =
      product.variants?.[0]?.id ||
      product.product_variants?.[0]?.id ||
      product.variant_id;
    if (!variantId) {
      created.push('تنبيه: لا يوجد شكل للمنتج ' + name);
      continue;
    }

    await api(token, 'POST', '/inventory/movements', {
      warehouse_id: warehouse.id,
      variant_id: variantId,
      movement_type: 'IN',
      quantity: qty,
      unit_cost: cost,
      notes: 'رصيد تجريبي',
    });
    created.push('كمية ' + qty + ' من ' + name);
  }

  const customers = [
    ['علي حسن', '07701110001', 'بغداد - الكرادة', 'RETAIL'],
    ['سارة كريم', '07702220002', 'بغداد - المنصور', 'RETAIL'],
    ['محل الأمين', '07803330003', 'بغداد - الشورجة', 'WHOLESALE'],
    ['أبو محمد', '07704440004', 'البصرة - العشار', 'RETAIL'],
  ];
  const existingCustomers = rows(
    await api(token, 'GET', '/customers?page=1&limit=100'),
  );
  for (const [name, phone, address, type] of customers) {
    if (existingCustomers.some((item) => item.name === name)) continue;
    try {
      await api(token, 'POST', '/customers', {
        name,
        phone,
        address,
        type,
        credit_limit: 500000,
        notes: 'زبون تجريبي',
      });
    } catch (error) {
      if (!String(error.message).includes('type')) throw error;
      await api(token, 'POST', '/customers', {
        name,
        phone,
        address,
        credit_limit: 500000,
        notes: 'زبون تجريبي',
      });
    }
    created.push('زبون: ' + name);
  }

  const suppliers = rows(await api(token, 'GET', '/suppliers?page=1&limit=100'));
  if (!suppliers.some((item) => item.name === 'شركة النور للتجارة')) {
    await api(token, 'POST', '/suppliers', {
      name: 'شركة النور للتجارة',
      phone: '07705550005',
      address: 'بغداد - الكاظمية',
      notes: 'شركة تجريبية للقبض والدفع',
      credit_limit: 2000000,
    });
    created.push('شركة: شركة النور للتجارة');
  }

  const reps = rows(await api(token, 'GET', '/representatives?page=1&limit=100'));
  if (!reps.some((item) => item.name === 'أحمد المندوب')) {
    await api(token, 'POST', '/representatives', {
      name: 'أحمد المندوب',
      username: 'demo.rep',
      password: 'Demo@123456',
      phone: '07706660006',
      commission_rate: 5,
      office_name: 'مكتب الكرادة',
      office_phone: '07807770007',
      office_address: 'بغداد - الكرادة داخل',
    });
    created.push('مندوب: أحمد المندوب');
  }

  const companyPayload = await api(token, 'GET', '/company');
  const company = companyPayload.data || companyPayload;
  const settings =
    company.settings && typeof company.settings === 'object'
      ? { ...company.settings }
      : {};
  settings.usd_exchange_rate = '1310';
  settings.document_layouts = {
    ...(settings.document_layouts || {}),
    header: {
      office_name: 'مكتب سايلر التجريبي',
      address: 'بغداد - الكرادة - شارع الصناعة',
      description: 'مواد غذائية ومنظفات بالجملة والمفرد',
      phone: '07700000001',
      phone2: '07800000002',
    },
  };
  await api(token, 'PATCH', '/company', {
    name: company.name || 'مكتب سايلر التجريبي',
    phone: company.phone || '07700000001',
    address: company.address || 'بغداد - الكرادة - شارع الصناعة',
    email: company.email || 'info@sayler.app',
    settings,
  });
  created.push('إعدادات الشركة وسعر الدولار 1310');

  console.log(created.length ? created.join('\n') : 'البيانات التجريبية موجودة مسبقاً');
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});

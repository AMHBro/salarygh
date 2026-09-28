import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

// تعريف كافة صلاحيات النظام مع التركيز على صلاحيات الاعتماد (Approve) والإدارة
const SYSTEM_PERMISSIONS = [
  // فروع
  { resource: 'branches', action: 'create', description: 'إنشاء فرع جديد' },
  { resource: 'branches', action: 'read', description: 'عرض تفاصيل وقائمة الفروع' },
  { resource: 'branches', action: 'update', description: 'تعديل بيانات الفرع' },
  { resource: 'branches', action: 'delete', description: 'حذف الفرع' },
  { resource: 'branches', action: 'submit', description: 'إرسال الفرع للاعتماد' },
  { resource: 'branches', action: 'approve', description: 'اعتماد وتفعيل الفرع' },
  { resource: 'branches', action: 'reject', description: 'رفض طلب الفرع' },
  { resource: 'branches', action: 'disable', description: 'تعطيل الفرع' },
  { resource: 'branches', action: 'assign_manager', description: 'تعيين مدير الفرع' },

  // مخازن
  { resource: 'warehouses', action: 'create', description: 'إنشاء مخزن جديد' },
  { resource: 'warehouses', action: 'read', description: 'عرض تفاصيل وقائمة المخازن' },
  { resource: 'warehouses', action: 'update', description: 'تعديل بيانات المخزن' },
  { resource: 'warehouses', action: 'delete', description: 'حذف المخزن' },
  { resource: 'warehouses', action: 'submit', description: 'إرسال المخزن للاعتماد' },
  { resource: 'warehouses', action: 'approve', description: 'اعتماد وتفعيل المخزن' },
  { resource: 'warehouses', action: 'reject', description: 'رفض طلب المخزن' },
  { resource: 'warehouses', action: 'disable', description: 'تعطيل المخزن' },
  { resource: 'warehouses', action: 'assign_keepers', description: 'تعيين أمناء المخزن' },

  // شركة وتنظيم
  { resource: 'company', action: 'create', description: 'تهيئة بيانات الشركة' },
  { resource: 'company', action: 'read', description: 'عرض بيانات الشركة' },
  { resource: 'company', action: 'update', description: 'تحديث إعدادات وبيانات الشركة' },
  { resource: 'organization', action: 'read', description: 'عرض شجرة الهيكل التنظيمي' },
  { resource: 'organization', action: 'approve', description: 'اعتماد عناصر الهيكل التنظيمي' },

  // مشتريات وفواتير شراء
  { resource: 'purchases', action: 'create', description: 'إنشاء فاتورة شراء' },
  { resource: 'purchases', action: 'read', description: 'عرض فواتير الشراء' },
  { resource: 'purchases', action: 'update', description: 'تعديل فاتورة شراء' },
  { resource: 'purchases', action: 'delete', description: 'إلغاء أو حذف فاتورة شراء' },
  { resource: 'purchases', action: 'approve', description: 'اعتماد وترحيل فاتورة الشراء' },

  // موردين ودفعات موردين
  { resource: 'suppliers', action: 'create', description: 'إضافة مورد جديد' },
  { resource: 'suppliers', action: 'read', description: 'عرض الموردين' },
  { resource: 'suppliers', action: 'update', description: 'تعديل بيانات مورد' },
  { resource: 'suppliers', action: 'delete', description: 'حذف مورد' },
  { resource: 'supplier_payments', action: 'create', description: 'إنشاء سند صرف / دفعة مورد' },
  { resource: 'supplier_payments', action: 'read', description: 'عرض دفعات الموردين' },
  { resource: 'supplier_payments', action: 'approve', description: 'اعتماد دفعة المورد' },

  // مخزون وحركات
  { resource: 'inventory', action: 'create', description: 'إجراء حركة مخزون' },
  { resource: 'inventory', action: 'read', description: 'عرض حركة وأرصدة المخزون' },
  { resource: 'inventory', action: 'transfer', description: 'تحويل بضاعة بين المخازن' },
  { resource: 'inventory', action: 'adjust', description: 'تسوية رصيد المخزون' },
  { resource: 'inventory', action: 'approve', description: 'اعتماد تسويات وحركات المخزون' },

  // تحويلات مخزنية
  { resource: 'warehouse_transfers', action: 'create', description: 'إنشاء طلب تحويل مخزني' },
  { resource: 'warehouse_transfers', action: 'read', description: 'عرض طلبات التحويل المخزني' },
  { resource: 'warehouse_transfers', action: 'approve', description: 'اعتماد وموافقة التحويل المخزني' },
  { resource: 'warehouse_transfers', action: 'dispatch', description: 'إرسال وشحن التحويل المخزني' },
  { resource: 'warehouse_transfers', action: 'receive', description: 'استلام التحويل المخزني' },

  // جرد وتسويات
  { resource: 'stocktaking', action: 'create', description: 'بدء جلسة جرد مخزني' },
  { resource: 'stocktaking', action: 'read', description: 'عرض جلسات الجرد' },
  { resource: 'stocktaking', action: 'update', description: 'إدخال كميات الجرد' },
  { resource: 'stocktaking', action: 'approve', description: 'اعتماد ومطابقة نتائج الجرد' },
  { resource: 'stocktaking', action: 'reconcile', description: 'ترحيل الفروقات الجردية' },

  // منتجات وتصنيفات ووحدات
  { resource: 'products', action: 'create', description: 'إضافة منتج جديد' },
  { resource: 'products', action: 'read', description: 'عرض المنتجات' },
  { resource: 'products', action: 'update', description: 'تعديل منتج' },
  { resource: 'products', action: 'delete', description: 'حذف منتج' },
  { resource: 'categories', action: 'create', description: 'إضافة تصنيف' },
  { resource: 'categories', action: 'read', description: 'عرض التصنيفات' },
  { resource: 'categories', action: 'update', description: 'تعديل تصنيف' },
  { resource: 'categories', action: 'delete', description: 'حذف تصنيف' },
  { resource: 'units', action: 'create', description: 'إضافة وحدة قياس' },
  { resource: 'units', action: 'read', description: 'عرض وحدات القياس' },
  { resource: 'units', action: 'update', description: 'تعديل وحدة قياس' },
  { resource: 'units', action: 'delete', description: 'حذف وحدة قياس' },

  // عملاء ومبيعات
  { resource: 'customers', action: 'create', description: 'إضافة عميل جديد' },
  { resource: 'customers', action: 'read', description: 'عرض قائمة العملاء' },
  { resource: 'customers', action: 'update', description: 'تعديل بيانات عميل' },
  { resource: 'customers', action: 'delete', description: 'حذف عميل' },
  { resource: 'direct_sales', action: 'create', description: 'إنشاء فاتورة مبيعات مباشرة (POS)' },
  { resource: 'direct_sales', action: 'read', description: 'عرض فواتير المبيعات' },
  { resource: 'direct_sales', action: 'void', description: 'إلغاء فاتورة مبيعات' },
  { resource: 'direct_sales', action: 'return', description: 'إنشاء مرتجع مبيعات' },
  { resource: 'direct_sales', action: 'approve', description: 'اعتماد الخصومات أو المرتجعات' },

  // مندوبين وعهد
  { resource: 'representatives', action: 'create', description: 'إضافة مندوب مبيعات' },
  { resource: 'representatives', action: 'read', description: 'عرض المندوبين' },
  { resource: 'representatives', action: 'update', description: 'تعديل بيانات مندوب' },
  { resource: 'rep_custody', action: 'create', description: 'إنشاء طلب عهدة لمندوب' },
  { resource: 'rep_custody', action: 'read', description: 'عرض طلبات وحسابات العهد' },
  { resource: 'rep_custody', action: 'dispatch', description: 'تسليم وتجهيز العهدة' },
  { resource: 'rep_custody', action: 'settle', description: 'تسوية ومطابقة عهدة المندوب' },
  { resource: 'rep_custody', action: 'approve', description: 'اعتماد طلب العهدة أو تسويتها' },

  // مستخدمين وأدوار
  { resource: 'users', action: 'create', description: 'إنشاء مستخدم جديد' },
  { resource: 'users', action: 'read', description: 'عرض المستخدمين' },
  { resource: 'users', action: 'update', description: 'تعديل مستخدم' },
  { resource: 'users', action: 'delete', description: 'حذف أو تعطيل مستخدم' },
  { resource: 'roles', action: 'create', description: 'إنشاء دور جديد' },
  { resource: 'roles', action: 'read', description: 'عرض الأدوار والصلاحيات' },
  { resource: 'roles', action: 'update', description: 'تعديل الأدوار والصلاحيات' },
  { resource: 'roles', action: 'delete', description: 'حذف دور' },
  { resource: 'roles', action: 'assign', description: 'إسناد وتعيين الصلاحيات للأدوار' },

  // تقارير ولوحة التحكم
  { resource: 'dashboard', action: 'read', description: 'عرض لوحة التحكم والإحصائيات' },
  { resource: 'reports', action: 'read', description: 'عرض وتصدير التقارير' },
];

// الأدوار الافتراضية
const SYSTEM_ROLES = [
  { name: 'ADMIN', description: 'مدير النظام — صلاحيات كاملة وشاملة لكافة العمليات والاعتمادات', is_system: true },
  { name: 'MANAGER', description: 'مدير الفرع — إدارة ومتابعة أعمال الفرع والمخازن التابعة', is_system: true },
  { name: 'WAREHOUSE', description: 'أمين المخزن — إدارة الحركات المخزنية والجرد والاستلام', is_system: true },
  { name: 'CASHIER', description: 'كاشير — إدارة المبيعات المباشرة والفواتير اليومية', is_system: true },
  { name: 'REP', description: 'مندوب المبيعات — إدارة مبيعات الميدان والعهد', is_system: true },
];

async function main() {
  console.log('🚀 Starting Super User & Permissions Seeding...');

  // 1. إنشاء / تحديث الصلاحيات في جدول permissions
  console.log(`📦 Upserting ${SYSTEM_PERMISSIONS.length} permissions...`);
  const permissionMap = new Map<string, string>(); // resource:action -> permission_id

  for (const perm of SYSTEM_PERMISSIONS) {
    const record = await prisma.permissions.upsert({
      where: {
        resource_action: {
          resource: perm.resource,
          action: perm.action,
        },
      },
      update: {
        description: perm.description,
      },
      create: {
        resource: perm.resource,
        action: perm.action,
        description: perm.description,
      },
    });
    permissionMap.set(`${perm.resource}:${perm.action}`, record.id);
  }
  console.log('✅ All permissions have been registered.');

  // 2. إنشاء / تحديث الأدوار في جدول roles
  console.log('👑 Ensuring system roles exist...');
  const roleMap = new Map<string, string>(); // name -> role_id

  for (const role of SYSTEM_ROLES) {
    const record = await prisma.roles.upsert({
      where: { name: role.name },
      update: {
        description: role.description,
        is_system: role.is_system,
      },
      create: {
        name: role.name,
        description: role.description,
        is_system: role.is_system,
      },
    });
    roleMap.set(role.name, record.id);
  }

  const adminRoleId = roleMap.get('ADMIN')!;

  // 3. ربط كافة الصلاحيات (100% Full Permissions) بدور ADMIN
  console.log('🔗 Assigning ALL permissions to ADMIN role...');
  const allPermissionIds = Array.from(permissionMap.values());

  for (const permId of allPermissionIds) {
    await prisma.role_permissions.upsert({
      where: {
        role_id_permission_id: {
          role_id: adminRoleId,
          permission_id: permId,
        },
      },
      update: {},
      create: {
        role_id: adminRoleId,
        permission_id: permId,
      },
    });
  }
  console.log(`✅ Granted ${allPermissionIds.length} permissions to role [ADMIN].`);

  // 4. إنشاء / تحديث مستخدم السوبر يوزر الأساسي
  const superuserUsername = 'admin';
  const superuserEmail = 'admin@sayler.app';
  const superuserPasswordRaw = 'Admin@123456';
  const salt = await bcrypt.genSalt(10);
  const passwordHash = await bcrypt.hash(superuserPasswordRaw, salt);

  console.log(`👤 Creating/updating Super User [${superuserUsername}]...`);
  const superUser = await prisma.users.upsert({
    where: { username: superuserUsername },
    update: {
      email: superuserEmail,
      full_name: 'مدير النظام (Super User)',
      password_hash: passwordHash,
      role_id: adminRoleId,
      is_active: true,
    },
    create: {
      username: superuserUsername,
      email: superuserEmail,
      full_name: 'مدير النظام (Super User)',
      password_hash: passwordHash,
      role_id: adminRoleId,
      is_active: true,
    },
  });

  // تحديث أي مستخدم تجريبي موجود ليكون مرتبطاً بدور إذا رغبنا (اختياري)
  const existingAhmed = await prisma.users.findUnique({ where: { username: 'ahmed_ali' } });
  if (existingAhmed && !existingAhmed.role_id) {
    await prisma.users.update({
      where: { id: existingAhmed.id },
      data: { role_id: adminRoleId },
    });
    console.log('ℹ️ Assigned ADMIN role to existing user [ahmed_ali].');
  }

  let company = await prisma.companies.findFirst({
    where: { name: 'شركة سايلر' },
  });
  if (!company) {
    company = await prisma.companies.create({
      data: {
        name: 'شركة سايلر',
        email: superuserEmail,
      },
    });
  }

  const branch = await prisma.branches.upsert({
    where: { code: 'HQ-001' },
    update: {
      name: 'الفرع الرئيسي',
      type: 'HEADQUARTERS',
      status: 'ACTIVE',
      company_id: company.id,
      manager_id: superUser.id,
    },
    create: {
      code: 'HQ-001',
      name: 'الفرع الرئيسي',
      type: 'HEADQUARTERS',
      status: 'ACTIVE',
      company_id: company.id,
      created_by: superUser.id,
      manager_id: superUser.id,
    },
  });

  await prisma.users.update({
    where: { id: superUser.id },
    data: { branch_id: branch.id },
  });

  console.log(`🏢 Active branch: ${branch.name} (${branch.code})`);

  console.log('\n=============================================');
  console.log('🎉 Super User Setup Completed Successfully!');
  console.log('=============================================');
  console.log(`• Username: ${superUser.username}`);
  console.log(`• Email:    ${superUser.email}`);
  console.log(`• Password: ${superuserPasswordRaw}`);
  console.log(`• Role:     ADMIN (Full Access & Approvals)`);
  console.log(`• Status:   Active`);
  console.log(`• Total Permissions Assigned: ${allPermissionIds.length}`);
  console.log('=============================================\n');
}

main()
  .catch((e) => {
    console.error('❌ Seeding failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

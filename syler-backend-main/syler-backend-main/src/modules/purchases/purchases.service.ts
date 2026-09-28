import { Injectable, NotFoundException, BadRequestException, Logger } from '@nestjs/common';
import { pageWindow } from '../../common/paging';
import { PrismaService } from 'src/prisma/prisma.service';
import { CreatePurchaseInvoiceDto } from './dto/create-purchase.dto';
import { QuickAddProductDto } from './dto/quick-add-item.dto';
import { purchase_status_enum, purchase_payment_enum, price_type_enum, movement_type_enum } from '@prisma/client';


@Injectable()
export class PurchasesService {
    private readonly logger = new Logger(PurchasesService.name);

    constructor(
        private readonly prisma: PrismaService,
    ) { }

    private amountInIqd(dto: CreatePurchaseInvoiceDto, value: number): number {
        const amount = Number(value) || 0;
        if (dto.currency !== 'USD') {
            return amount;
        }
        const rate = Number(dto.exchange_rate ?? 0);
        if (!(rate > 0)) {
            throw new BadRequestException('سعر صرف الدولار مطلوب للشراء بالدولار');
        }
        return amount * rate;
    }

    private async generateInvoiceNumber(): Promise<string> {
        const today = new Date();
        const prefix = `PUR-${today.getFullYear()}${String(today.getMonth() + 1).padStart(2, '0')}-`;

        // البحث عن أعلى رقم فاتورة للشهر الحالي بدلاً من count() لتجنب تصادم القيد الفريد
        const latest = await this.prisma.purchase_invoices.findFirst({
            where: { invoice_number: { startsWith: prefix } },
            orderBy: { invoice_number: 'desc' },
            select: { invoice_number: true },
        });

        let nextNumber = 1;
        if (latest?.invoice_number) {
            const parts = latest.invoice_number.split('-');
            const lastSeq = parseInt(parts[parts.length - 1], 10);
            if (!isNaN(lastSeq)) nextNumber = lastSeq + 1;
        }

        return `${prefix}${String(nextNumber).padStart(4, '0')}`;
    }

    async createDirectInvoice(dto: CreatePurchaseInvoiceDto, userId: string) {
        if (!dto.items || dto.items.length === 0) {
            throw new BadRequestException('يجب إضافة مادة واحدة على الأقل في الفاتورة');
        }
        if (Number(dto.discount_amount ?? 0) !== 0 || dto.items.some(item => Number(item.discount_percent ?? 0) !== 0)) {
            throw new BadRequestException('الخصومات غير مفعلة في النظام');
        }

        // 1. التحقق من وجود المورد والمخزن
        const [supplier, warehouse] = await Promise.all([
            this.prisma.suppliers.findUnique({ where: { id: dto.supplier_id } }),
            this.prisma.warehouses.findUnique({ where: { id: dto.warehouse_id } }),
        ]);
        if (!supplier) throw new NotFoundException(`المورد غير موجود (id: ${dto.supplier_id})`);
        if (!warehouse) throw new NotFoundException(`المخزن غير موجود (id: ${dto.warehouse_id})`);

        // 2. التحقق المسبق من وجود جميع المواد والوحدات (لمنع Foreign Key Violation داخل Transaction)
        const variantIds = [...new Set(dto.items.map(i => i.variant_id))];
        const unitIds = [...new Set(dto.items.map(i => i.unit_id))];

        const [foundVariants, foundUnits] = await Promise.all([
            this.prisma.product_variants.findMany({
                where: { id: { in: variantIds } },
                select: { id: true, is_active: true },
            }),
            this.prisma.units_of_measure.findMany({
                where: { id: { in: unitIds } },
                select: { id: true },
            }),
        ]);

        const foundVariantIds = new Set(foundVariants.map(v => v.id));
        const foundUnitIds = new Set(foundUnits.map(u => u.id));

        const missingVariants = variantIds.filter(id => !foundVariantIds.has(id));
        const missingUnits = unitIds.filter(id => !foundUnitIds.has(id));

        if (missingVariants.length > 0) {
            throw new BadRequestException(
                `المواد التالية غير موجودة في السيرفر، تأكد من مزامنة المنتجات أولاً: [${missingVariants.join(', ')}]`
            );
        }
        if (missingUnits.length > 0) {
            throw new BadRequestException(
                `وحدات القياس التالية غير موجودة في السيرفر، تأكد من مزامنة وحدات القياس أولاً: [${missingUnits.join(', ')}]`
            );
        }

        // 3. حساب المجاميع المالية بالدينار. unit_cost بدون currency يبقى ديناراً كما ترسله الحاسبة بعد التحويل.
        let subtotal = 0;
        for (const item of dto.items) {
            const unitCost = this.amountInIqd(dto, item.unit_cost);
            const gross = item.quantity * unitCost;
            const lineDiscount = ((item.discount_percent || 0) / 100) * gross;
            subtotal += gross - lineDiscount;
        }

        const discountAmount = this.amountInIqd(dto, Number(dto.discount_amount) || 0);
        const total = Math.max(0, subtotal - discountAmount);

        let paidAmount = 0;
        let dueAmount = 0;

        if (dto.payment_type === purchase_payment_enum.CASH) {
            paidAmount = total;
            dueAmount = 0;
        } else if (dto.payment_type === purchase_payment_enum.CREDIT) {
            paidAmount = 0;
            dueAmount = total;
        } else if (dto.payment_type === purchase_payment_enum.PARTIAL) {
            paidAmount = this.amountInIqd(dto, Number(dto.paid_amount) || 0);
            if (paidAmount > total) throw new BadRequestException('المبلغ المدفوع لا يمكن أن يتجاوز إجمالي الفاتورة');
            dueAmount = total - paidAmount;
        }

        // 4. التحقق من الحد الائتماني للمورد (BR-PUR-002)
        if (dueAmount > 0) {
            const newTotalBalance = Number(supplier.balance) + dueAmount;
            const creditLimit = Number(supplier.credit_limit);
            if (creditLimit > 0 && newTotalBalance > creditLimit) {
                throw new BadRequestException(`تجاوز الحد الائتماني للمورد! الحد المسموح: ${creditLimit}، الرصيد الحالي: ${supplier.balance}`);
            }
        }

        const invoiceNumber = await this.generateInvoiceNumber();

        // 5. تنفيذ العملية داخل Database Transaction ذرية
        try {
            return await this.prisma.$transaction(async (tx) => {
                const variantIds = [...new Set(dto.items.map((item) => item.variant_id))].sort();
                for (const variantId of variantIds) {
                    await tx.$queryRaw`SELECT id FROM product_variants WHERE id = ${variantId}::uuid FOR UPDATE`;
                }

                // أ. إنشاء سجل الفاتورة (مع دعم الـ Local ID اختياري)
                const invoiceData: any = {
                    invoice_number: invoiceNumber,
                    supplier_id: dto.supplier_id,
                    warehouse_id: dto.warehouse_id,
                    status: purchase_status_enum.CONFIRMED,
                    payment_type: dto.payment_type,
                    subtotal,
                    discount_amount: discountAmount,
                    total,
                    paid_amount: paidAmount,
                    // due_amount يحسبه PostgreSQL تلقائياً
                    notes: dto.notes,
                    created_by: userId,
                };

                // استخدام الـ Local ID إذا تم تمريره وكان غير مستخدم مسبقاً
                if (dto.id) {
                    const existing = await tx.purchase_invoices.findUnique({ where: { id: dto.id } });
                    if (existing) {
                        throw new BadRequestException(`فاتورة بهذا المعرف موجودة مسبقاً (id: ${dto.id})، تم ترحيلها سابقاً.`);
                    }
                    invoiceData.id = dto.id;
                }

                const invoice = await tx.purchase_invoices.create({ data: invoiceData });

                // ب. إدخال أسطر المواد وتحديث المخزون والتكلفة
                for (const item of dto.items) {
                    const unitCost = this.amountInIqd(dto, item.unit_cost);
                    const gross = item.quantity * unitCost;
                    const itemLineTotal =
                        gross - ((item.discount_percent || 0) / 100) * gross;

                    await tx.purchase_invoice_items.create({
                        data: {
                            invoice_id: invoice.id,
                            variant_id: item.variant_id,
                            unit_id: item.unit_id,
                            quantity: item.quantity,
                            quantity_in_base_unit: item.quantity,
                            unit_cost: unitCost,
                            cost_per_base_unit: unitCost,
                            discount_percent: item.discount_percent || 0,
                            total_price: itemLineTotal,
                        },
                    });

                    const stockTotals = await tx.stock_levels.aggregate({
                        where: { variant_id: item.variant_id },
                        _sum: { quantity_on_hand: true },
                    });
                    const oldQtyAll = Number(stockTotals._sum.quantity_on_hand ?? 0);

                    // زيادة رصيد المخزن المحدد (Upsert في stock_levels)
                    const stock = await tx.stock_levels.findUnique({
                        where: {
                            variant_id_warehouse_id: {
                                variant_id: item.variant_id,
                                warehouse_id: dto.warehouse_id,
                            },
                        },
                    });
                    const currentQty = stock ? Number(stock.quantity_on_hand) : 0;
                    const newQty = currentQty + Number(item.quantity);

                    await tx.stock_levels.upsert({
                        where: {
                            variant_id_warehouse_id: {
                                variant_id: item.variant_id,
                                warehouse_id: dto.warehouse_id,
                            },
                        },
                        update: { quantity_on_hand: newQty, updated_at: new Date() },
                        create: {
                            variant_id: item.variant_id,
                            warehouse_id: dto.warehouse_id,
                            quantity_on_hand: item.quantity,
                        },
                    });

                    // تسجيل حركة دخول مخزني في inventory_movements
                    await tx.inventory_movements.create({
                        data: {
                            movement_type: movement_type_enum.IN,
                            variant_id: item.variant_id,
                            warehouse_id: dto.warehouse_id,
                            quantity: item.quantity,
                            unit_cost: unitCost,
                            reference_type: 'PURCHASE_INVOICE',
                            reference_id: invoice.id,
                            performed_by: userId,
                        },
                    });

                    // تحديث المتوسط المرجح للتكلفة (WAC) في product_variants
                    const variant = await tx.product_variants.findUnique({ where: { id: item.variant_id } });
                    if (variant) {
                        const oldCost = Number(variant.weighted_avg_cost) || 0;
                        const incoming = Number(item.quantity);
                        const newGlobal = oldQtyAll + incoming;
                        const weightedCost =
                            newGlobal > 0
                                ? (oldQtyAll * oldCost + incoming * unitCost) / newGlobal
                                : unitCost;
                        await tx.product_variants.update({
                            where: { id: item.variant_id },
                            data: {
                                weighted_avg_cost: weightedCost,
                                last_purchase_price: unitCost,
                                updated_at: new Date(),
                            },
                        });
                    }
                }

                // ج. تحديث رصيد ذمة المورد بالمبلغ المتبقي
                if (dueAmount > 0) {
                    await tx.suppliers.update({
                        where: { id: dto.supplier_id },
                        data: {
                            balance: { increment: dueAmount },
                            updated_at: new Date(),
                        },
                    });
                }

                return invoice;
            });
        } catch (err) {
            // تسجيل الخطأ الكامل في السيرفر مع Stack Trace لسهولة التتبع
            this.logger.error(
                `[createDirectInvoice] فشلت عملية إنشاء فاتورة الشراء - supplier: ${dto.supplier_id}, warehouse: ${dto.warehouse_id}`,
                err instanceof Error ? err.stack : String(err),
            );
            throw err;
        }
    }

    // ─── الإضافة السريعة لمادة جديدة من داخل الفاتورة (Quick Add) ─────────────
    async quickAddProduct(dto: QuickAddProductDto, userId?: string) {
        // 1. فحص وجود وحدة قياس وتصنيف افتراضيين
        let [defaultUnit, defaultCategory] = await Promise.all([
            this.prisma.units_of_measure.findFirst({ where: { is_base_unit: true, is_active: true } }),
            this.prisma.categories.findFirst({ where: { is_active: true } }),
        ]);

        if (!defaultUnit) {
            defaultUnit = await this.prisma.units_of_measure.create({
                data: { name_ar: 'قطعة', is_base_unit: true },
            });
        }
        if (!defaultCategory) {
            defaultCategory = await this.prisma.categories.create({
                data: { name_ar: 'عام' },
            });
        }

        return this.prisma.$transaction(async (tx) => {
            // إنشاء المنتج
            const product = await tx.products.create({
                data: {
                    name_ar: dto.name_ar,
                    barcode: dto.barcode,
                    category_id: defaultCategory.id,
                    base_unit_id: defaultUnit.id,
                    created_by: userId,
                },
            });

            // إنشاء الشكل Variant والأسعار التقديرية
            const variant = await tx.product_variants.create({
                data: {
                    product_id: product.id,
                    barcode: dto.barcode,
                    weighted_avg_cost: dto.unit_cost,
                    last_purchase_price: dto.unit_cost,
                },
            });

            // تسجيل سعر الكلفة
            await tx.product_prices.create({
                data: {
                    variant_id: variant.id,
                    unit_id: defaultUnit.id,
                    price_type: price_type_enum.COST,
                    price: dto.unit_cost,
                },
            });

            return {
                variant_id: variant.id,
                product_id: product.id,
                name_ar: product.name_ar,
                barcode: product.barcode,
                unit_id: defaultUnit.id,
                unit_name: defaultUnit.name_ar,
                unit_cost: dto.unit_cost,
                quantity: dto.quantity,
            };
        });
    }

    async findAll(query: any) {
        const { page, limit, skip } = pageWindow(query);

        const where: any = {};
        if (query.supplier_id) where.supplier_id = query.supplier_id;
        if (query.warehouse_id) where.warehouse_id = query.warehouse_id;
        if (query.payment_type) where.payment_type = query.payment_type;
        if (query.search) {
            where.OR = [
                { invoice_number: { contains: query.search, mode: 'insensitive' } },
                { supplier: { name: { contains: query.search, mode: 'insensitive' } } },
            ];
        }

        const [total, data] = await Promise.all([
            this.prisma.purchase_invoices.count({ where }),
            this.prisma.purchase_invoices.findMany({
                where,
                skip,
                take: limit,
                include: {
                    supplier: { select: { id: true, name: true, phone: true } },
                    warehouse: { select: { id: true, name: true } },
                    _count: { select: { purchase_invoice_items: true } },
                },
                orderBy: { created_at: 'desc' },
            }),
        ]);

        return {
            data,
            meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
        };
    }

    // ─── تفاصيل فاتورة واحدة ──────────────────────────────────────────────────
    async findOne(id: string) {
        const invoice = await this.prisma.purchase_invoices.findUnique({
            where: { id },
            include: {
                supplier: true,
                warehouse: true,
                purchase_invoice_items: {
                    include: {
                        product_variants: { include: { products: true } },
                        units_of_measure: true,
                    },
                },
            },
        });
        if (!invoice) throw new NotFoundException('فاتورة الشراء غير موجودة');
        return invoice;
    }

}

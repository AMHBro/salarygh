import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';

import { PrismaService } from 'src/prisma/prisma.service';
import { FloorService } from '../floor/floor.service';

import { CreateDirectSaleDto } from './dto/create-direct-sale.dto';

import {
  price_type_enum,
} from '@prisma/client';

import {
  SalesTransactionService,
} from './sales-transaction.service';

@Injectable()
export class DirectSalesService {
  constructor(
    private readonly prisma: PrismaService,

    private readonly salesTransactionService:
      SalesTransactionService,

    private readonly floor: FloorService,
  ) { }

  /**
   * ============================================================
   * 1. POS PRODUCTS
   * ============================================================
   */
  async getPosProducts(query: {
    warehouse_id?: string;
    price_type?: price_type_enum;
    search?: string;
  }) {
    const priceType =
      query.price_type ??
      price_type_enum.RETAIL;

    const where: any = {
      is_active: true,
    };

    if (query.search) {
      where.OR = [
        {
          name_ar: {
            contains:
              query.search,

            mode:
              'insensitive',
          },
        },

        {
          barcode: {
            contains:
              query.search,

            mode:
              'insensitive',
          },
        },

        {
          sku: {
            contains:
              query.search,

            mode:
              'insensitive',
          },
        },
      ];
    }

    const products =
      await this.prisma.products.findMany({
        where,

        include: {
          units_of_measure: {
            select: {
              id: true,
              name_ar: true,
              symbol: true,
            },
          },

          product_variants: {
            where: {
              is_active: true,
            },

            include: {
              product_prices: {
                where: {
                  is_active: true,
                },
              },

              stock_levels:
                query.warehouse_id
                  ? {
                    where: {
                      warehouse_id:
                        query.warehouse_id,
                    },
                  }
                  : true,
            },
          },
        },

        orderBy: {
          name_ar: 'asc',
        },
      });

    const posItems: any[] =
      [];

    for (
      const product of products
    ) {
      for (
        const variant of
        product.product_variants
      ) {
        const targetPrice =
          variant.product_prices.find(
            (price) =>
              price.price_type ===
              priceType,
          );

        const retailPrice =
          variant.product_prices.find(
            (price) =>
              price.price_type ===
              price_type_enum.RETAIL,
          );

        const wholesalePrice =
          variant.product_prices.find(
            (price) =>
              price.price_type ===
              price_type_enum.WHOLESALE,
          );

        /**
         * available =
         * quantity_on_hand - quantity_reserved
         */
        const availableQty =
          (
            variant.stock_levels ??
            []
          ).reduce(
            (
              total,
              stock,
            ) =>
              total +
              Number(
                stock.quantity_on_hand ??
                0,
              ) -
              Number(
                stock.quantity_reserved ??
                0,
              ),

            0,
          );

        posItems.push({
          product_id:
            product.id,

          variant_id:
            variant.id,

          name:
            product.name_ar,

          barcode:
            variant.barcode ??
            product.barcode ??
            '—',

          sku:
            variant.sku ??
            product.sku ??
            '—',

          unit_id:
            product.base_unit_id,

          unit_name:
            product
              .units_of_measure
              ?.name_ar,

          price:
            Number(
              targetPrice?.price ??
              retailPrice?.price ??
              0,
            ),

          retail_price:
            Number(
              retailPrice?.price ??
              0,
            ),

          wholesale_price:
            Number(
              wholesalePrice?.price ??
              0,
            ),

          quantity_available:
            availableQty,

          is_out_of_stock:
            availableQty <= 0,
        });
      }
    }

    return posItems;
  }

  /**
   * ============================================================
   * 2. CREATE DIRECT SALE
   * ============================================================
   */
  async createDirectSale(
    dto: CreateDirectSaleDto,
    userId?: string,
  ) {
    if (
      !dto.items ||
      dto.items.length === 0
    ) {
      throw new BadRequestException(
        'يجب إضافة مادة واحدة على الأقل في الفاتورة',
      );
    }

    /**
     * مفتاح الحاسبة ثابت عبر إعادة الإرسال.
     * الطلبات المباشرة بلا مفتاح تحصل على مفتاح خادم لمرة واحدة.
     */
    const providedKey = dto.idempotency_key?.trim();
    const idempotencyKey =
      providedKey && providedKey.length > 0
        ? providedKey
        : `POS-${Date.now()}-${Math.random()
            .toString(36)
            .substring(2, 10)}`;

    try {
      return await this.prisma.$transaction(
      async (tx) => {
        /**
         * ======================================================
         * تنفيذ عملية البيع من خلال Sales Core
         * ======================================================
         */
        const result =
          await this.salesTransactionService.createSale(
            tx,
            {
              customer_id:
                dto.customer_id ??
                null,

              /**
               * البيع المباشر ليس طلب مندوب.
               */
              rep_id:
                null,

              warehouse_id:
                dto.warehouse_id,

              price_type:
                dto.price_type,

              payment_type:
                dto.payment_type,

              discount_amount:
                dto.discount_amount ??
                0,

              paid_amount:
                dto.paid_amount ??
                0,

              notes:
                dto.notes ??
                null,

              idempotency_key:
                idempotencyKey,

              hold_keys:
                dto.hold_keys,

              created_by:
                userId ??
                null,

              items:
                dto.items.map(
                  (item) => ({
                    variant_id:
                      item.variant_id,

                    unit_id:
                      item.unit_id,

                    quantity:
                      item.quantity,

                    unit_price:
                      item.unit_price,

                    discount_percent:
                      item.discount_percent ??
                      0,
                  }),
                ),
            },
          );

        /**
         * ======================================================
         * Invoice هو مصدر الحقيقة للنتيجة المالية
         * ======================================================
         *
         * لا نستخدم:
         *
         * result.totals.total
         * result.totals.paid_amount
         * result.totals.due_amount
         *
         * لأن invoice نفسه يحتوي هذه القيم.
         */
        const invoice =
          result.invoice;

        /**
         * ======================================================
         * Customer name
         * ======================================================
         *
         * حتى لا نعتمد أيضًا على اختلاف Shape
         * الخاص بـ result.customer_name.
         */
        let customerName =
          'زبون نقدي عام';

        if (
          invoice.customer_id
        ) {
          const customer =
            await tx.customers.findUnique({
              where: {
                id:
                  invoice.customer_id,
              },

              select: {
                name:
                  true,
              },
            });

          if (
            customer?.name
          ) {
            customerName =
              customer.name;
          }
        }

        /**
         * ======================================================
         * RESPONSE
         * ======================================================
         */
        return {
          id:
            invoice.id,

          already_exists:
            result.already_exists === true,

          invoice_number:
            invoice.invoice_number,

          customer_name:
            customerName,

          /**
           * الحل هنا:
           *
           * نأخذ القيم مباشرة من Invoice.
           */
          total:
            Number(
              invoice.total,
            ),

          paid_amount:
            Number(
              invoice.paid_amount,
            ),

          due_amount:
            Number(
              invoice.due_amount,
            ),

          payment_type:
            invoice.payment_type,

          status:
            invoice.status,

          created_at:
            invoice.created_at,
        };
      },
    );
    } catch (error) {
      const response =
        typeof (error as { getResponse?: () => unknown })?.getResponse ===
        'function'
          ? (error as { getResponse: () => unknown }).getResponse()
          : null;
      const body =
        response && typeof response === 'object'
          ? (response as { code?: string; message?: string; details?: { variant_id?: string; warehouse_id?: string } })
          : null;
      if (body?.code === 'INSUFFICIENT_STOCK' && body.details?.variant_id) {
        await this.floor.lockShortage({
          variantId: body.details.variant_id,
          warehouseId: body.details.warehouse_id,
          saleKey: idempotencyKey,
          reason: body.message ?? 'الكمية غير كافية',
        }).catch(() => undefined);
      }
      throw error;
    }
  }

  /**
   * ============================================================
   * 3. SALES INVOICES LIST
   * ============================================================
   */
  async findAll(
    query: any,
  ) {
    const page =
      Math.max(
        1,
        Number(
          query.page,
        ) || 1,
      );

    const limit =
      Math.min(
        100,
        Math.max(
          1,
          Number(
            query.limit,
          ) || 20,
        ),
      );

    const skip =
      (page - 1) *
      limit;

    const where: any = {};

    if (
      query.customer_id
    ) {
      where.customer_id =
        query.customer_id;
    }

    if (
      query.warehouse_id
    ) {
      where.warehouse_id =
        query.warehouse_id;
    }

    if (
      query.payment_type
    ) {
      where.payment_type =
        query.payment_type;
    }

    if (
      query.search
    ) {
      where.OR = [
        {
          invoice_number: {
            contains:
              query.search,

            mode:
              'insensitive',
          },
        },

        {
          customers: {
            name: {
              contains:
                query.search,

              mode:
                'insensitive',
            },
          },
        },
      ];
    }

    const [
      total,
      items,
    ] =
      await Promise.all([
        this.prisma
          .sales_invoices
          .count({
            where,
          }),

        this.prisma
          .sales_invoices
          .findMany({
            where,

            skip,

            take:
              limit,

            include: {
              customers: {
                select: {
                  id:
                    true,

                  name:
                    true,

                  phone:
                    true,
                },
              },

              warehouses: {
                select: {
                  id:
                    true,

                  name:
                    true,
                },
              },

              _count: {
                select: {
                  sales_invoice_items:
                    true,
                },
              },
            },

            orderBy: {
              created_at:
                'desc',
            },
          }),
      ]);

    const data =
      items.map(
        (invoice) => ({
          id:
            invoice.id,

          invoice_number:
            invoice.invoice_number,

          customer_name:
            invoice.customers
              ?.name ??
            'زبون نقدي عام',

          warehouse_name:
            invoice.warehouses
              ?.name ??
            '—',

          total:
            Number(
              invoice.total,
            ),

          paid_amount:
            Number(
              invoice.paid_amount,
            ),

          due_amount:
            Number(
              invoice.due_amount,
            ),

          payment_type:
            invoice.payment_type,

          status:
            invoice.status,

          items_count:
            invoice._count
              .sales_invoice_items,

          created_at:
            invoice.created_at,
        }),
      );

    return {
      data,

      meta: {
        total,

        page,

        limit,

        totalPages:
          Math.ceil(
            total /
            limit,
          ),
      },
    };
  }

  /**
   * ============================================================
   * 4. SALES INVOICE DETAILS
   * ============================================================
   */
  async findOne(
    id: string,
  ) {
    const invoice =
      await this.prisma.sales_invoices.findUnique({
        where: {
          id,
        },

        include: {
          customers:
            true,

          warehouses:
            true,

          sales_invoice_items: {
            include: {
              product_variants: {
                include: {
                  products:
                    true,
                },
              },

              units_of_measure:
                true,
            },
          },
        },
      });

    if (
      !invoice
    ) {
      throw new NotFoundException(
        'فاتورة المبيعات غير موجودة',
      );
    }

    return invoice;
  }
}
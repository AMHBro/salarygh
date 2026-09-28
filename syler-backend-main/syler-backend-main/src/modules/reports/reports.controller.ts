import {
    applyDecorators,
    Controller,
    Get,
    Query,
    Request,
    UseGuards,
} from '@nestjs/common';
import {
    ApiBearerAuth,
    ApiForbiddenResponse,
    ApiOperation,
    ApiQuery,
    ApiTags,
    ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { Roles } from '../../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { ReportsService } from './reports.service';

type ReportQuery = Record<string, string | undefined>;

/**
 * الفلاتر مشتركة بين عدة تقارير.
 * الصلاحية والنطاق الفعلي للفرع يُحددهما ReportsService.
 */
function BranchFilter() {
    return applyDecorators(
        ApiQuery({
            name: 'branch_id',
            required: false,
            type: String,
            format: 'uuid',
            description:
                'للأدمن فقط: تحديد فرع. حساب المكتب يُقيَّد بفرعه تلقائياً.',
        }),
    );
}

function WarehouseFilter() {
    return applyDecorators(
        ApiQuery({
            name: 'warehouse_id',
            required: false,
            type: String,
            format: 'uuid',
            description: 'تحديد مخزن ضمن نطاق الفرع المسموح.',
        }),
    );
}

function DateFilters() {
    return applyDecorators(
        ApiQuery({
            name: 'from',
            required: false,
            type: String,
            example: '2026-09-01',
            description: 'بداية الفترة بالتوقيت المحلي لبغداد، YYYY-MM-DD.',
        }),
        ApiQuery({
            name: 'to',
            required: false,
            type: String,
            example: '2026-09-30',
            description: 'نهاية الفترة بالتوقيت المحلي لبغداد، YYYY-MM-DD.',
        }),
    );
}

function PaginationFilters() {
    return applyDecorators(
        ApiQuery({
            name: 'page',
            required: false,
            type: Number,
            example: 1,
            description: 'رقم الصفحة؛ الافتراضي 1.',
        }),
        ApiQuery({
            name: 'limit',
            required: false,
            type: Number,
            example: 50,
            description: 'عدد السجلات؛ الافتراضي 50 والأقصى 100.',
        }),
    );
}

@ApiTags('M09 - Reports')
@ApiBearerAuth()
@ApiUnauthorizedResponse({
    description: 'رمز الدخول مفقود أو غير صالح.',
})
@ApiForbiddenResponse({
    description: 'المستخدم لا يملك صلاحية التقارير أو طلب بيانات خارج فرعه.',
})
@UseGuards(JwtAuthGuard)
@Roles('ADMIN', 'SUPER_ADMIN', 'MANAGER')
@Controller('reports')
export class ReportsController {
    constructor(private readonly reports: ReportsService) { }

    // ────────────────── الزبائن ──────────────────

    @Get('customers/directory')
    @ApiOperation({
        summary: 'تقرير أسماء جميع الزبائن',
        description:
            'يعرض أسماء الزبائن وبيانات التواصل والمندوب. الأدمن يرى الجميع؛ المكتب يرى الزبائن المرتبطين بفرعه. لا تُعرض معرّفات الربط في النتيجة.',
    })
    @BranchFilter()
    @PaginationFilters()
    @ApiQuery({
        name: 'search',
        required: false,
        type: String,
        description: 'البحث باسم الزبون أو رقم الهاتف.',
    })
    customers(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.customers(req.user.id, query);
    }

    @Get('customers/balances')
    @ApiOperation({
        summary: 'الرصيد الإجمالي للزبائن: دائن ومدين',
        description:
            'يعرض مجموع الأرصدة الحالية الدائنة والمدينة وعدد الزبائن. متاح للأدمن فقط لأن رصيد الزبون مخزن عالمياً ولا يمكن تقسيمه بدقة بين الفروع.',
    })
    customerBalances(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.customerBalances(req.user.id, query);
    }

    @Get('customers/statement')
    @ApiOperation({
        summary: 'كشف حساب زبون معين',
        description:
            'يعرض الفواتير ودفعات البيع وسندات القبض والرصيد المتحرك، مرتبة زمنياً. يُستخدم customer_id لتحديد الزبون في الطلب فقط، ولا يظهر في نتيجة التقرير. الدفعات القديمة غير المسجلة بسند مؤرخ قد لا تظهر بتاريخها الأصلي.',
    })
    @BranchFilter()
    @DateFilters()
    @PaginationFilters()
    @ApiQuery({
        name: 'customer_id',
        required: true,
        type: String,
        format: 'uuid',
        description: 'الزبون المطلوب استخراج كشف حسابه.',
    })
    customerStatement(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.customerStatement(req.user.id, query);
    }

    // ────────────────── المواد ──────────────────

    @Get('products/prices')
    @ApiOperation({
        summary: 'تقرير أسعار البيع',
        description:
            'يعرض أسعار بيع المنتجات الفعالة حسب نوع السعر ووحدة القياس. الأسعار معرفة للمنتج، وليست منفصلة لكل فرع.',
    })
    @PaginationFilters()
    prices(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.prices(req.user.id, query);
    }

    @Get('products/expiry')
    @ApiOperation({
        summary: 'تقرير انتهاء صلاحية المواد',
        description:
            'يعرض دفعات المواد التي انتهت صلاحيتها أو ستنتهي خلال عدد الأيام المحدد. تظهر الدفعات التي سُجل لها تاريخ صلاحية وكمية متبقية فقط.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @PaginationFilters()
    @ApiQuery({
        name: 'days',
        required: false,
        type: Number,
        example: 30,
        description:
            'عرض المنتهي وما سينتهي خلال هذا العدد من الأيام؛ الافتراضي 30.',
    })
    expiry(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.expiry(req.user.id, query);
    }

    @Get('products/stock')
    @ApiOperation({
        summary: 'جرد أرصدة المواد',
        description:
            'يعرض الرصيد الفعلي والمحجوز والمتاح وقيمة المخزون لكل مادة ومخزن، اعتماداً على stock_levels.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @PaginationFilters()
    stock(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.stock(req.user.id, query, false);
    }

    @Get('products/below-reorder')
    @ApiOperation({
        summary: 'جرد المواد دون مستوى إعادة الطلب',
        description:
            'يعرض المواد التي تقل كميتها المتاحة عن min_stock_level المحدد للمنتج داخل المخزن.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @PaginationFilters()
    belowReorder(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.stock(req.user.id, query, true);
    }

    @Get('products/sales')
    @ApiOperation({
        summary: 'مجموع المبيعات حسب المواد',
        description:
            'يجمع الكميات المباعة وقيمة بنود البيع وعدد الفواتير لكل مادة، باستثناء الفواتير المسودة والملغاة والمرتجعة.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    @PaginationFilters()
    productSales(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.productSales(req.user.id, query);
    }

    @Get('products/purchase-analysis')
    @ApiOperation({
        summary: 'كشف تحليل المشتريات',
        description:
            'يعرض بنود فواتير الشراء مع المورد والمادة والمخزن والكمية والتكلفة، باستثناء الفواتير المسودة والملغاة.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    @PaginationFilters()
    purchaseAnalysis(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.purchaseAnalysis(req.user.id, query);
    }

    @Get('products/sales-analysis')
    @ApiOperation({
        summary: 'كشف تحليل المبيعات',
        description:
            'يعرض تفاصيل بنود البيع مع الزبون والمادة والمخزن والسعر والكمية. فواتير المتجر الإلكتروني المقبولة تظهر بعد تحويلها إلى فاتورة بيع.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    @PaginationFilters()
    salesAnalysis(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.salesAnalysis(req.user.id, query);
    }

    @Get('products/monthly-purchases')
    @ApiOperation({
        summary: 'مخطط المشتريات حسب الأشهر',
        description:
            'يعيد الشهر وعدد فواتير الشراء ومجموع قيمتها؛ تستخدمه الواجهة لرسم المخطط البياني.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    monthlyPurchases(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.monthlyPurchases(req.user.id, query);
    }

    @Get('products/monthly-sales')
    @ApiOperation({
        summary: 'مخطط المبيعات حسب الأشهر',
        description:
            'يعيد الشهر وعدد فواتير البيع ومجموع قيمتها بتوقيت بغداد؛ تستخدمه الواجهة لرسم المخطط البياني.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    monthlySales(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.monthlySales(req.user.id, query);
    }

    @Get('products/movements')
    @ApiOperation({
        summary: 'حركة مادة معينة خلال فترة',
        description:
            'يعرض حركات الدخول والخروج والتحويل والتسوية لمتغير مادة محدد. variant_id يُستخدم لتحديد المادة في الطلب ولا يظهر في النتائج.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    @PaginationFilters()
    @ApiQuery({
        name: 'variant_id',
        required: true,
        type: String,
        format: 'uuid',
        description: 'متغير المادة المطلوب عرض حركاته.',
    })
    movements(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.movements(req.user.id, query);
    }

    // ────────────────── الصندوق ──────────────────

    @Get('cash/daily')
    @ApiOperation({
        summary: 'التقرير اليومي للصندوق',
        description:
            'يعرض إجمالي المقبوضات والمدفوعات وصافي الحركة لكل يوم وصندوق. يعتمد على الحركات النقدية المسجلة والمرتبطة بصندوق.',
    })
    @BranchFilter()
    @DateFilters()
    @PaginationFilters()
    cashDaily(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.cashDaily(req.user.id, query);
    }

    @Get('cash/balances')
    @ApiOperation({
        summary: 'كشف رصيد الصندوق',
        description:
            'يعرض الرصيد الافتتاحي لآخر جلسة والحركات المسجلة بعدها والرصيد المحسوب. دقته تعتمد على اكتمال جلسات الصندوق وربط كل حركة به.',
    })
    @BranchFilter()
    @PaginationFilters()
    cashBalances(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.cashBalances(req.user.id, query);
    }

    @Get('cash/receipts')
    @ApiOperation({
        summary: 'كشف المقبوضات',
        description:
            'يعرض المقبوضات النقدية المسجلة، بما فيها قبض البيع وسندات قبض الزبائن المرتبطة بالصندوق.',
    })
    @BranchFilter()
    @DateFilters()
    @PaginationFilters()
    cashReceipts(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.cashEntries(
            req.user.id,
            query,
            'receipts',
        );
    }

    @Get('cash/payments')
    @ApiOperation({
        summary: 'كشف المدفوعات',
        description:
            'يعرض سندات الدفع النقدية المرتبطة بالصندوق، مثل سداد فواتير الموردين.',
    })
    @BranchFilter()
    @DateFilters()
    @PaginationFilters()
    cashPayments(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.cashEntries(
            req.user.id,
            query,
            'payments',
        );
    }

    @Get('cash/vouchers')
    @ApiOperation({
        summary: 'تقرير السندات',
        description:
            'يعرض سندات القبض والدفع، وطريقة الدفع والطرف المرتبط والسند والفاتورة إن وجدت.',
    })
    @BranchFilter()
    @DateFilters()
    @PaginationFilters()
    vouchers(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.vouchers(req.user.id, query);
    }

    // ────────────────── الأرباح ──────────────────

    @Get('profits/by-customer')
    @ApiOperation({
        summary: 'مجموع الأرباح حسب الزبائن',
        description:
            'يعرض المبيعات والتكلفة والربح الإجمالي لكل زبون. الربح لا يشمل المصاريف والعمولات.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    @PaginationFilters()
    profitByCustomer(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.profits(
            req.user.id,
            query,
            'customer',
        );
    }

    @Get('profits/by-product')
    @ApiOperation({
        summary: 'مجموع الأرباح حسب المواد',
        description:
            'يعرض المبيعات والتكلفة والربح الإجمالي لكل مادة اعتماداً على تكلفة البند المحفوظة وقت البيع.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    @PaginationFilters()
    profitByProduct(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.profits(
            req.user.id,
            query,
            'product',
        );
    }

    @Get('profits/analysis')
    @ApiOperation({
        summary: 'كشف تحليل الأرباح',
        description:
            'يعرض قيمة المبيعات والتكلفة والربح الإجمالي حسب الفاتورة، ضمن الفترة والفرع أو المخزن المحدد.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    @PaginationFilters()
    profitAnalysis(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.profits(
            req.user.id,
            query,
            'invoice',
        );
    }

    @Get('products/discounts')
    @ApiOperation({
        summary: 'تقرير بخصومات البيع',
        description:
            'يعرض فواتير البيع التي عليها خصم على الفاتورة أو على بنودها.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @DateFilters()
    @PaginationFilters()
    salesDiscounts(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.salesDiscounts(req.user.id, query);
    }

    @Get('products/missing-invoices')
    @ApiOperation({
        summary: 'أرقام قوائم البيع المفقودة',
        description:
            'يستخرج الفجوات في الجزء الرقمي من أرقام فواتير البيع. الرقم فريد على مستوى النظام لذلك لا يُقسَّم حسب الفرع.',
    })
    @PaginationFilters()
    missingSalesInvoices(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.missingSalesInvoices(req.user.id, query);
    }

    @Get('products/raw-materials')
    @ApiOperation({
        summary: 'تقرير بأرصدة المواد الأولية',
        description:
            'أرصدة المواد المرتبطة بتصنيف يحتوي «أولي» أو «خام». المواد بلا هذا التصنيف لا تظهر.',
    })
    @BranchFilter()
    @WarehouseFilter()
    @PaginationFilters()
    rawMaterialBalances(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.rawMaterialBalances(req.user.id, query);
    }

    @Get('cash/exchange-rate')
    @ApiOperation({
        summary: 'تقرير أسعار صرف الدولار',
        description:
            'يعرض سعر صرف الدولار المحفوظ في إعدادات الشركة. يُضبط من شاشة الإعدادات.',
    })
    exchangeRate(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.exchangeRate(req.user.id, query);
    }

    @Get('profits/capital')
    @ApiOperation({
        summary: 'تقرير رأس المال',
        description:
            'تقدير: قيمة المخزون + ذمم الزبائن المدينة + رصيد الصندوق − ذمم الموردين. ذمم الزبائن والموردين عامة وليست مفصولة بالفرع.',
    })
    @BranchFilter()
    @WarehouseFilter()
    capital(
        @Request() req: any,
        @Query() query: ReportQuery,
    ) {
        return this.reports.capital(req.user.id, query);
    }

    // @Get('availability')
    // @ApiOperation({
    //     summary: 'حالة توفر التقارير',
    //     description:
    //         'يعرض التقارير التي تحتاج بيانات إضافية، مثل أسعار صرف الدولار ورأس المال، والتقارير التي تعتمد دقتها على اكتمال الحركات.',
    // })
    // availability(@Request() req: any) {
    //     return this.reports.availability(req.user.id);
    // }
}
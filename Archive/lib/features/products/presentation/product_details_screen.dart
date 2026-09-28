import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';

class ProductDetailsScreen extends StatelessWidget {
  final ProductModel product;

  const ProductDetailsScreen({
    super.key,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    final activeVariants = product.variants
        .where(
          (variant) => variant.deletedAt == null,
    )
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            34,
            30,
            34,
            34,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(
                context,
              ),
              const SizedBox(
                height: 26,
              ),
              _buildProductHero(),
              const SizedBox(
                height: 18,
              ),
              _buildStats(
                activeVariants,
              ),
              const SizedBox(
                height: 18,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildGeneralInfo(),
                  ),
                  const SizedBox(
                    width: 16,
                  ),
                  Expanded(
                    flex: 2,
                    child: _buildProductFlags(),
                  ),
                ],
              ),
              const SizedBox(
                height: 18,
              ),
              _buildPricing(),
              const SizedBox(
                height: 18,
              ),
              _buildVariantsSection(
                activeVariants,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader(
      BuildContext context,
      ) {
    return Row(
      children: [
        IconButton(
          tooltip: 'رجوع',
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_rounded,
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppTheme.primaryTextColor,
                ),
              ),
              const SizedBox(
                height: 5,
              ),
              const Text(
                'تفاصيل المنتج والأسعار والخيارات المرتبطة به.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        _StatusBadge(
          text: product.isActive
              ? 'فعال'
              : 'موقوف',
          type: product.isActive
              ? _BadgeType.success
              : _BadgeType.neutral,
        ),
        const SizedBox(
          width: 8,
        ),
        _StatusBadge(
          text: product.isSynced
              ? 'على السيرفر'
              : 'بانتظار المزامنة',
          type: product.isSynced
              ? _BadgeType.success
              : _BadgeType.warning,
          icon: product.isSynced
              ? Icons.cloud_done_outlined
              : Icons.cloud_upload_outlined,
        ),
      ],
    );
  }

  // ===========================================================================
  // HERO
  // ===========================================================================

  Widget _buildProductHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        22,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFF1D1D1F,
        ),
        borderRadius: BorderRadius.circular(
          18,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(
                15,
              ),
            ),
            child: Icon(
              product.hasRealVariants
                  ? Icons.account_tree_outlined
                  : Icons.inventory_2_outlined,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(
            width: 16,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (product.nameEn.trim().isNotEmpty) ...[
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    product.nameEn,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(
                        0xFFB8B8BD,
                      ),
                    ),
                  ),
                ],
                const SizedBox(
                  height: 7,
                ),
                Text(
                  product.description.trim().isNotEmpty
                      ? product.description
                      : 'لا يوجد وصف مسجل لهذا المنتج.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: Color(
                      0xFFB8B8BD,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _HeroInfo(
            title: 'التصنيف',
            value: product.category,
          ),
          const SizedBox(
            width: 34,
          ),
          _HeroInfo(
            title: 'الوحدة',
            value: product.unit,
          ),
          const SizedBox(
            width: 34,
          ),
          _HeroInfo(
            title: 'النوع',
            value: product.hasRealVariants
                ? 'متعدد الخيارات'
                : 'منتج عادي',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STATS
  // ===========================================================================

  Widget _buildStats(
      List<ProductVariantModel> variants,
      ) {
    final activeVariants = variants
        .where(
          (variant) => variant.isActive,
    )
        .length;

    final syncedVariants = variants
        .where(
          (variant) => variant.isSynced,
    )
        .length;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'عدد الخيارات',
            value: '${variants.length}',
            subtitle: 'Variants مرتبطة بالمنتج',
            icon: Icons.account_tree_outlined,
            highlighted: true,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'الخيارات الفعالة',
            value: '$activeVariants',
            subtitle: 'متاحة للاستخدام والبيع',
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'على السيرفر',
            value: '$syncedVariants',
            subtitle: 'خيارات تمت مزامنتها',
            icon: Icons.cloud_done_outlined,
          ),
        ),
        const SizedBox(
          width: 14,
        ),
        Expanded(
          child: _StatCard(
            title: 'الحد الأدنى',
            value: _formatNumber(
              product.minimumStock,
            ),
            subtitle: 'حد تنبيه المخزون',
            icon: Icons.warning_amber_rounded,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // GENERAL INFO
  // ===========================================================================

  Widget _buildGeneralInfo() {
    return _SectionCard(
      title: 'معلومات المنتج',
      subtitle: 'البيانات الأساسية والتعريفية للمنتج.',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _InfoField(
                  title: 'اسم المنتج',
                  value: product.name,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: _InfoField(
                  title: 'الاسم الإنكليزي',
                  value: product.nameEn.trim().isEmpty
                      ? '—'
                      : product.nameEn,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 12,
          ),
          Row(
            children: [
              Expanded(
                child: _InfoField(
                  title: 'باركود المنتج',
                  value: product.barcode.trim().isEmpty
                      ? '—'
                      : product.barcode,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: _InfoField(
                  title: 'SKU',
                  value: product.sku?.trim().isNotEmpty == true
                      ? product.sku!
                      : '—',
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 12,
          ),
          Row(
            children: [
              Expanded(
                child: _InfoField(
                  title: 'التصنيف',
                  value: product.category,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: _InfoField(
                  title: 'وحدة القياس',
                  value: product.unit,
                ),
              ),
            ],
          ),
          if (product.description.trim().isNotEmpty) ...[
            const SizedBox(
              height: 12,
            ),
            _InfoField(
              title: 'الوصف',
              value: product.description,
              multiline: true,
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // FLAGS
  // ===========================================================================

  Widget _buildProductFlags() {
    return _SectionCard(
      title: 'خصائص المنتج',
      subtitle: 'إعدادات وسلوك المنتج داخل النظام.',
      child: Column(
        children: [
          _FeatureRow(
            icon: Icons.account_tree_outlined,
            title: 'يحتوي على خيارات',
            enabled: product.hasVariants,
          ),
          const Divider(
            height: 24,
            color: AppTheme.subtleBorderColor,
          ),
          _FeatureRow(
            icon: Icons.event_outlined,
            title: 'تاريخ صلاحية',
            enabled: product.hasExpiry,
          ),
          const Divider(
            height: 24,
            color: AppTheme.subtleBorderColor,
          ),
          _FeatureRow(
            icon: Icons.numbers_rounded,
            title: 'رقم تسلسلي',
            enabled: product.hasSerial,
          ),
          const Divider(
            height: 24,
            color: AppTheme.subtleBorderColor,
          ),
          _FeatureRow(
            icon: Icons.sell_outlined,
            title: 'حالة المنتج',
            enabled: product.isActive,
            enabledText: 'فعال',
            disabledText: 'موقوف',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PRICING
  // ===========================================================================

  Widget _buildPricing() {
    return _SectionCard(
      title: product.hasRealVariants
          ? 'الأسعار الأساسية'
          : 'أسعار المنتج',
      subtitle: product.hasRealVariants
          ? 'الأسعار الافتراضية للمنتج، ويمكن أن يملك كل خيار أسعاراً مختلفة.'
          : 'مستويات الأسعار المستخدمة في عمليات البيع.',
      child: Row(
        children: [
          Expanded(
            child: _PriceCard(
              title: 'سعر الكلفة',
              value: product.costPrice,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: _PriceCard(
              title: 'سعر المندوب',
              value: product.representativePrice,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: _PriceCard(
              title: 'سعر الجملة',
              value: product.wholesalePrice,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: _PriceCard(
              title: 'سعر التجزئة',
              value: product.retailPrice,
              highlighted: true,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // VARIANTS
  // ===========================================================================

  Widget _buildVariantsSection(
      List<ProductVariantModel> variants,
      ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(
              20,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'خيارات المنتج',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryTextColor,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                      ),
                      Text(
                        'الصفات والباركود والأسعار الخاصة بكل Variant.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFF5F5F7,
                    ),
                    borderRadius: BorderRadius.circular(
                      20,
                    ),
                  ),
                  child: Text(
                    '${variants.length} خيارات',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            color: AppTheme.subtleBorderColor,
          ),
          if (variants.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 50,
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 36,
                    color: AppTheme.tertiaryTextColor,
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  Text(
                    'لا توجد خيارات مرتبطة بهذا المنتج.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            const _VariantsHeader(),
            ...variants.map(
                  (variant) => _VariantDetailsRow(
                variant: variant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// VARIANT ROW
// =============================================================================

class _VariantDetailsRow extends StatelessWidget {
  final ProductVariantModel variant;

  const _VariantDetailsRow({
    required this.variant,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 82,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.subtleBorderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variant.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryTextColor,
                  ),
                ),
                if (variant.attributes.isNotEmpty) ...[
                  const SizedBox(
                    height: 5,
                  ),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: variant.attributes.entries.map(
                          (entry) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF5F5F7,
                            ),
                            borderRadius: BorderRadius.circular(
                              12,
                            ),
                          ),
                          child: Text(
                            '${_attributeName(entry.key)}: ${entry.value}',
                            style: const TextStyle(
                              fontSize: 8.5,
                              color: AppTheme.secondaryTextColor,
                            ),
                          ),
                        );
                      },
                    ).toList(),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _SmallValue(
              primary: variant.barcode.trim().isEmpty
                  ? '—'
                  : variant.barcode,
              secondary: variant.sku?.trim().isNotEmpty == true
                  ? 'SKU: ${variant.sku}'
                  : 'بدون SKU',
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                variant.costPrice,
              ),
              style: const TextStyle(
                fontSize: 10.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                variant.representativePrice,
              ),
              style: const TextStyle(
                fontSize: 10.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                variant.wholesalePrice,
              ),
              style: const TextStyle(
                fontSize: 10.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatMoney(
                variant.retailPrice,
              ),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: _SmallValue(
              primary: _formatMoney(
                variant.weightedAverageCost,
              ),
              secondary: 'آخر شراء: ${_formatMoney(variant.lastPurchasePrice)}',
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: _StatusBadge(
                text: variant.isActive
                    ? 'فعال'
                    : 'موقوف',
                type: variant.isActive
                    ? _BadgeType.success
                    : _BadgeType.neutral,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: _StatusBadge(
                text: variant.isSynced
                    ? 'مزامن'
                    : 'محلي',
                type: variant.isSynced
                    ? _BadgeType.success
                    : _BadgeType.warning,
                icon: variant.isSynced
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// VARIANT HEADER
// =============================================================================

class _VariantsHeader extends StatelessWidget {
  const _VariantsHeader();

  static const _style = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w500,
    color: AppTheme.secondaryTextColor,
  );

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      color: const Color(
        0xFFF8F8FA,
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'الخيار / الصفات',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Barcode / SKU',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الكلفة',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'المندوب',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الجملة',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'التجزئة',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'متوسط الكلفة',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الحالة',
              style: _style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'المزامنة',
              style: _style,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SECTION
// =============================================================================

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryTextColor,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 17,
          ),
          child,
        ],
      ),
    );
  }
}

// =============================================================================
// INFO FIELD
// =============================================================================

class _InfoField extends StatelessWidget {
  final String title;
  final String value;
  final bool multiline;

  const _InfoField({
    required this.title,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFFF8F8FA,
        ),
        borderRadius: BorderRadius.circular(
          11,
        ),
        border: Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 9.5,
              color: AppTheme.tertiaryTextColor,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            value,
            maxLines: multiline
                ? null
                : 1,
            overflow: multiline
                ? null
                : TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FEATURE
// =============================================================================

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool enabled;

  final String enabledText;
  final String disabledText;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.enabled,
    this.enabledText = 'نعم',
    this.disabledText = 'لا',
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(
              0xFFF5F5F7,
            ),
            borderRadius: BorderRadius.circular(
              10,
            ),
          ),
          child: Icon(
            icon,
            size: 17,
          ),
        ),
        const SizedBox(
          width: 11,
        ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        _StatusBadge(
          text: enabled
              ? enabledText
              : disabledText,
          type: enabled
              ? _BadgeType.success
              : _BadgeType.neutral,
        ),
      ],
    );
  }
}

// =============================================================================
// PRICE
// =============================================================================

class _PriceCard extends StatelessWidget {
  final String title;
  final double value;
  final bool highlighted;

  const _PriceCard({
    required this.title,
    required this.value,
    this.highlighted = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      padding: const EdgeInsets.all(
        15,
      ),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(
          0xFF1D1D1F,
        )
            : const Color(
          0xFFF8F8FA,
        ),
        borderRadius: BorderRadius.circular(
          13,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: highlighted
                  ? const Color(
                0xFFB8B8BD,
              )
                  : AppTheme.secondaryTextColor,
            ),
          ),
          const SizedBox(
            height: 7,
          ),
          Text(
            _formatMoney(
              value,
            ),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: highlighted
                  ? Colors.white
                  : AppTheme.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// HERO INFO
// =============================================================================

class _HeroInfo extends StatelessWidget {
  final String title;
  final String value;

  const _HeroInfo({
    required this.title,
    required this.value,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 9.5,
            color: Color(
              0xFF8E8E93,
            ),
          ),
        ),
        const SizedBox(
          height: 5,
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SMALL VALUE
// =============================================================================

class _SmallValue extends StatelessWidget {
  final String primary;
  final String secondary;

  const _SmallValue({
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(
          height: 3,
        ),
        Text(
          secondary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 8.5,
            color: AppTheme.tertiaryTextColor,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// BADGE
// =============================================================================

enum _BadgeType {
  success,
  warning,
  neutral,
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final _BadgeType type;
  final IconData? icon;

  const _StatusBadge({
    required this.text,
    required this.type,
    this.icon,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    late Color background;
    late Color foreground;

    switch (type) {
      case _BadgeType.success:
        background = const Color(
          0xFFEAF7EE,
        );
        foreground = const Color(
          0xFF248A3D,
        );
        break;

      case _BadgeType.warning:
        background = const Color(
          0xFFFFF4E5,
        );
        foreground = const Color(
          0xFFB26A00,
        );
        break;

      case _BadgeType.neutral:
        background = const Color(
          0xFFF2F2F4,
        );
        foreground = AppTheme.secondaryTextColor;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(
          20,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 12,
              color: foreground,
            ),
            const SizedBox(
              width: 4,
            ),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// STAT
// =============================================================================

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final bool highlighted;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.highlighted = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Container(
      height: 125,
      padding: const EdgeInsets.all(
        17,
      ),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(
          0xFF1D1D1F,
        )
            : Colors.white,
        borderRadius: BorderRadius.circular(
          17,
        ),
        border: highlighted
            ? null
            : Border.all(
          color: AppTheme.subtleBorderColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: highlighted
                        ? const Color(
                      0xFFB8B8BD,
                    )
                        : AppTheme.secondaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 6,
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: highlighted
                        ? Colors.white
                        : AppTheme.primaryTextColor,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: highlighted
                        ? const Color(
                      0xFF8E8E93,
                    )
                        : AppTheme.tertiaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: highlighted
                  ? Colors.white.withValues(
                alpha: 0.10,
              )
                  : const Color(
                0xFFF5F5F7,
              ),
              borderRadius: BorderRadius.circular(
                11,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: highlighted
                  ? Colors.white
                  : AppTheme.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FORMAT
// ===========================================================================

String _formatMoney(
    double value,
    ) {
  final text = value
      .toStringAsFixed(
    0,
  );

  final buffer = StringBuffer();

  for (var i = 0; i < text.length; i++) {
    if (i > 0 &&
        (text.length - i) % 3 == 0) {
      buffer.write(',');
    }

    buffer.write(
      text[i],
    );
  }

  return '${buffer.toString()} د.ع';
}

String _formatNumber(
    double value,
    ) {
  if (value == value.roundToDouble()) {
    return value
        .toInt()
        .toString();
  }

  return value.toStringAsFixed(
    2,
  );
}

String _attributeName(
    String key,
    ) {
  switch (key.trim().toLowerCase()) {
    case 'flavor':
      return 'النكهة';

    case 'size':
      return 'الحجم';

    case 'color':
      return 'اللون';

    case 'type':
      return 'النوع';

    case 'weight':
      return 'الوزن';

    default:
      return key;
  }
}
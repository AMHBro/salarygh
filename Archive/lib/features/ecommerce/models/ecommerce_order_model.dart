class EcommerceOrdersPage {
  final List<EcommerceOrderModel> orders;
  final int page;
  final int perPage;
  final int total;
  final int totalPages;

  const EcommerceOrdersPage({
    required this.orders,
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
  });

  factory EcommerceOrdersPage.fromJson(
      Map<String, dynamic> json,
      ) {
    final rawData = json['data'];
    final rawMeta = json['meta'];

    final meta = rawMeta is Map
        ? Map<String, dynamic>.from(rawMeta)
        : <String, dynamic>{};

    return EcommerceOrdersPage(
      orders: rawData is List
          ? rawData
          .whereType<Map>()
          .map(
            (item) => EcommerceOrderModel.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
          .toList()
          : const [],
      page: _toInt(meta['page'], fallback: 1),
      perPage: _toInt(meta['per_page'], fallback: 20),
      total: _toInt(meta['total']),
      totalPages: _toInt(meta['total_pages'], fallback: 1),
    );
  }

  static int _toInt(
      dynamic value, {
        int fallback = 0,
      }) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    ) ??
        fallback;
  }
}

class EcommerceOrderModel {
  final String id;
  final String orderNumber;

  final String source;
  final String status;

  final String? repId;

  final EcommerceRepresentativeModel? representative;
  final EcommercePartyModel? party;
  final EcommerceCustomerModel? customer;

  final String paymentType;

  final double subtotal;
  final double discountAmount;
  final double total;

  final String? notes;

  final DateTime? submittedAt;

  final DateTime? acceptedAt;
  final String? acceptedBy;

  final DateTime? rejectedAt;
  final String? rejectedBy;
  final String? rejectionReason;

  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancellationReason;

  final String? salesInvoiceId;

  final List<EcommerceOrderItemModel> items;

  const EcommerceOrderModel({
    required this.id,
    required this.orderNumber,
    required this.source,
    required this.status,
    required this.repId,
    required this.representative,
    required this.party,
    required this.customer,
    required this.paymentType,
    required this.subtotal,
    required this.discountAmount,
    required this.total,
    required this.notes,
    required this.submittedAt,
    required this.acceptedAt,
    required this.acceptedBy,
    required this.rejectedAt,
    required this.rejectedBy,
    required this.rejectionReason,
    required this.cancelledAt,
    required this.cancelledBy,
    required this.cancellationReason,
    required this.salesInvoiceId,
    required this.items,
  });

  factory EcommerceOrderModel.fromJson(
      Map<String, dynamic> json,
      ) {
    final rawItems = json['items'];

    return EcommerceOrderModel(
      id: _string(json['id']),
      orderNumber: _string(json['order_number']),
      source: _string(json['source']),
      status: _string(json['status']),
      repId: _nullableString(json['rep_id']),
      representative: EcommerceRepresentativeModel.tryFromJson(
        json['representative'],
      ),
      party: EcommercePartyModel.tryFromJson(
        json['party'],
      ),
      customer: EcommerceCustomerModel.tryFromJson(
        json['customer'],
      ),
      paymentType: _string(json['payment_type']),
      subtotal: _toDouble(json['subtotal']),
      discountAmount: _toDouble(
        json['discount_amount'],
      ),
      total: _toDouble(json['total']),
      notes: _nullableString(json['notes']),
      submittedAt: _date(json['submitted_at']),
      acceptedAt: _date(json['accepted_at']),
      acceptedBy: _nullableString(json['accepted_by']),
      rejectedAt: _date(json['rejected_at']),
      rejectedBy: _nullableString(json['rejected_by']),
      rejectionReason: _nullableString(
        json['rejection_reason'],
      ),
      cancelledAt: _date(json['cancelled_at']),
      cancelledBy: _nullableString(json['cancelled_by']),
      cancellationReason: _nullableString(
        json['cancellation_reason'],
      ),
      salesInvoiceId: _nullableString(
        json['sales_invoice_id'],
      ),
      items: rawItems is List
          ? rawItems
          .whereType<Map>()
          .map(
            (item) => EcommerceOrderItemModel.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
          .toList()
          : const [],
    );
  }

  bool get isSubmitted =>
      status.trim().toUpperCase() == 'SUBMITTED';

  bool get isAccepted =>
      status.trim().toUpperCase() == 'ACCEPTED';

  bool get isRejected =>
      status.trim().toUpperCase() == 'REJECTED';

  bool get isCancelled =>
      status.trim().toUpperCase() == 'CANCELLED';

  bool get isGuest =>
      source.trim().toUpperCase() == 'GUEST';

  bool get isRepresentative =>
      source.trim().toUpperCase() == 'REPRESENTATIVE';

  bool get isPartialPayment =>
      paymentType.trim().toUpperCase() == 'PARTIAL';

  String get sourceDisplayName {
    switch (source.trim().toUpperCase()) {
      case 'GUEST':
        return 'زبون متجر';

      case 'REPRESENTATIVE':
        return 'مندوب';

      default:
        return source;
    }
  }

  String get statusDisplayName {
    switch (status.trim().toUpperCase()) {
      case 'SUBMITTED':
        return 'بانتظار المعالجة';

      case 'ACCEPTED':
        return 'مقبول';

      case 'REJECTED':
        return 'مرفوض';

      case 'CANCELLED':
        return 'ملغي';

      default:
        return status;
    }
  }

  String get paymentTypeDisplayName {
    switch (paymentType.trim().toUpperCase()) {
      case 'CASH':
        return 'نقدي';

      case 'CREDIT':
        return 'آجل';

      case 'PARTIAL':
        return 'دفع جزئي';

      default:
        return paymentType;
    }
  }

  String get partyDisplayName {
    if (customer != null &&
        customer!.name.trim().isNotEmpty) {
      return customer!.name;
    }

    if (party != null &&
        party!.name.trim().isNotEmpty) {
      return party!.name;
    }

    if (representative != null &&
        representative!.name.trim().isNotEmpty) {
      return representative!.name;
    }

    return 'غير محدد';
  }

  String? get partyPhone {
    final customerPhone = customer?.phone.trim();

    if (customerPhone != null &&
        customerPhone.isNotEmpty) {
      return customerPhone;
    }

    final partyPhone = party?.phone?.trim();

    if (partyPhone != null &&
        partyPhone.isNotEmpty) {
      return partyPhone;
    }

    final repPhone = representative?.phone?.trim();

    if (repPhone != null &&
        repPhone.isNotEmpty) {
      return repPhone;
    }

    return null;
  }

  static String _string(
      dynamic value,
      ) {
    return value?.toString().trim() ?? '';
  }

  static String? _nullableString(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    return text.isEmpty ? null : text;
  }

  static double _toDouble(
      dynamic value,
      ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }

  static DateTime? _date(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }
}

class EcommerceCustomerModel {
  final String name;
  final String phone;
  final String? email;
  final String? address;

  const EcommerceCustomerModel({
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
  });

  factory EcommerceCustomerModel.fromJson(
      Map<String, dynamic> json,
      ) {
    return EcommerceCustomerModel(
      name: _string(json['name']),
      phone: _string(json['phone']),
      email: _nullableString(json['email']),
      address: _nullableString(json['address']),
    );
  }

  static EcommerceCustomerModel? tryFromJson(
      dynamic value,
      ) {
    if (value is! Map) {
      return null;
    }

    return EcommerceCustomerModel.fromJson(
      Map<String, dynamic>.from(value),
    );
  }
}

class EcommerceRepresentativeModel {
  final String id;
  final String name;
  final String? phone;
  final String? officeName;
  final String? officePhone;
  final String? officeAddress;

  const EcommerceRepresentativeModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.officeName,
    required this.officePhone,
    required this.officeAddress,
  });

  factory EcommerceRepresentativeModel.fromJson(
      Map<String, dynamic> json,
      ) {
    return EcommerceRepresentativeModel(
      id: _string(json['id']),
      name: _string(json['name']),
      phone: _nullableString(json['phone']),
      officeName: _nullableString(json['office_name']),
      officePhone: _nullableString(json['office_phone']),
      officeAddress: _nullableString(
        json['office_address'],
      ),
    );
  }

  static EcommerceRepresentativeModel? tryFromJson(
      dynamic value,
      ) {
    if (value is! Map) {
      return null;
    }

    return EcommerceRepresentativeModel.fromJson(
      Map<String, dynamic>.from(value),
    );
  }
}

class EcommercePartyModel {
  final String type;
  final String id;
  final String name;
  final String? phone;
  final String? address;

  const EcommercePartyModel({
    required this.type,
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
  });

  factory EcommercePartyModel.fromJson(
      Map<String, dynamic> json,
      ) {
    return EcommercePartyModel(
      type: _string(json['type']),
      id: _string(json['id']),
      name: _string(json['name']),
      phone: _nullableString(json['phone']),
      address: _nullableString(json['address']),
    );
  }

  static EcommercePartyModel? tryFromJson(
      dynamic value,
      ) {
    if (value is! Map) {
      return null;
    }

    return EcommercePartyModel.fromJson(
      Map<String, dynamic>.from(value),
    );
  }
}

class EcommerceOrderItemModel {
  final String id;
  final String orderId;
  final String productId;
  final String variantId;
  final String unitId;

  final String productName;
  final String unitName;

  final double quantity;

  final String priceType;

  final double basePrice;

  final String? commissionType;
  final double commissionValue;
  final double commissionAmount;

  final double unitPrice;
  final double lineTotal;

  final String? sku;
  final String? barcode;

  final DateTime? createdAt;

  const EcommerceOrderItemModel({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.variantId,
    required this.unitId,
    required this.productName,
    required this.unitName,
    required this.quantity,
    required this.priceType,
    required this.basePrice,
    required this.commissionType,
    required this.commissionValue,
    required this.commissionAmount,
    required this.unitPrice,
    required this.lineTotal,
    required this.sku,
    required this.barcode,
    required this.createdAt,
  });

  factory EcommerceOrderItemModel.fromJson(
      Map<String, dynamic> json,
      ) {
    final rawSnapshot = json['variant_snapshot'];

    final snapshot = rawSnapshot is Map
        ? Map<String, dynamic>.from(rawSnapshot)
        : <String, dynamic>{};

    return EcommerceOrderItemModel(
      id: _string(json['id']),
      orderId: _string(json['order_id']),
      productId: _string(json['product_id']),
      variantId: _string(json['variant_id']),
      unitId: _string(json['unit_id']),
      productName: _string(json['product_name']),
      unitName: _string(json['unit_name']),
      quantity: _toDouble(json['quantity']),
      priceType: _string(json['price_type']),
      basePrice: _toDouble(json['base_price']),
      commissionType: _nullableString(
        json['commission_type'],
      ),
      commissionValue: _toDouble(
        json['commission_value'],
      ),
      commissionAmount: _toDouble(
        json['commission_amount'],
      ),
      unitPrice: _toDouble(json['unit_price']),
      lineTotal: _toDouble(json['line_total']),
      sku: _nullableString(snapshot['sku']),
      barcode: _nullableString(snapshot['barcode']),
      createdAt: _date(json['created_at']),
    );
  }
}

class EcommerceAcceptResult {
  final String orderId;
  final String orderNumber;
  final String status;
  final String? salesInvoiceId;
  final String? invoiceNumber;
  final String? warehouseId;

  final double total;
  final double paidAmount;
  final double dueAmount;

  final String message;

  const EcommerceAcceptResult({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.salesInvoiceId,
    required this.invoiceNumber,
    required this.warehouseId,
    required this.total,
    required this.paidAmount,
    required this.dueAmount,
    required this.message,
  });

  factory EcommerceAcceptResult.fromJson(
      Map<String, dynamic> json,
      ) {
    final rawData = json['data'];

    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    return EcommerceAcceptResult(
      orderId: _string(data['order_id']),
      orderNumber: _string(data['order_number']),
      status: _string(data['status']),
      salesInvoiceId: _nullableString(
        data['sales_invoice_id'],
      ),
      invoiceNumber: _nullableString(
        data['invoice_number'],
      ),
      warehouseId: _nullableString(
        data['warehouse_id'],
      ),
      total: _toDouble(data['total']),
      paidAmount: _toDouble(data['paid_amount']),
      dueAmount: _toDouble(data['due_amount']),
      message: _string(json['message']),
    );
  }
}

// =============================================================================
// SHARED PARSING HELPERS
// =============================================================================

String _string(
    dynamic value,
    ) {
  return value?.toString().trim() ?? '';
}

String? _nullableString(
    dynamic value,
    ) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();

  return text.isEmpty ? null : text;
}

double _toDouble(
    dynamic value,
    ) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(
    value?.toString() ?? '',
  ) ??
      0;
}

DateTime? _date(
    dynamic value,
    ) {
  if (value == null) {
    return null;
  }

  return DateTime.tryParse(
    value.toString(),
  )?.toLocal();
}
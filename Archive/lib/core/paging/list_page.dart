import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// حجم الصفحة للقوائم الطويلة في التطبيق.
const int kListPageSize = 40;

int sqlInt(QueryRow row, String column) {
  final value = row.data[column];
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double sqlDouble(QueryRow row, String column) {
  final value = row.data[column];
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

class ListPage<T> {
  final List<T> items;
  final int total;

  const ListPage({
    required this.items,
    required this.total,
  });

  bool get hasMore => items.length < total;
}

class ListPagination extends StatelessWidget {
  final int page;
  final int totalItems;
  final int pageSize;
  final int? pageCount;
  final bool? hasNextPage;
  final bool loading;
  final ValueChanged<int>? onPageChanged;

  const ListPagination({
    super.key,
    required this.page,
    this.totalItems = 0,
    this.pageSize = kListPageSize,
    this.pageCount,
    this.hasNextPage,
    this.loading = false,
    this.onPageChanged,
  });

  int get totalPages {
    if (pageCount != null) {
      return pageCount! < 1 ? 1 : pageCount!;
    }
    if (totalItems <= 0) {
      return 1;
    }
    return (totalItems + pageSize - 1) ~/ pageSize;
  }

  bool get _hasNext => hasNextPage ?? page < totalPages;

  @override
  Widget build(BuildContext context) {
    if (page <= 1 && !_hasNext) {
      return const SizedBox.shrink();
    }

    final knownPages = hasNextPage == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'السابق',
            onPressed: loading || page <= 1
                ? null
                : () => onPageChanged?.call(page - 1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.subtleBorderColor),
            ),
            child: Text(
              knownPages ? '$page / $totalPages' : 'صفحة $page',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'التالي',
            onPressed: loading || !_hasNext
                ? null
                : () => onPageChanged?.call(page + 1),
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_left_rounded),
          ),
        ],
      ),
    );
  }
}

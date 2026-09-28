import 'package:flutter/material.dart';

import '../../../core/paging/list_page.dart';
import '../data/alira_catalog.dart';
import '../data/alira_mock.dart';
import '../data/alira_store_orders.dart';
import 'alira_frame.dart';
import 'alira_product_image.dart';

class AliraShopApp extends StatefulWidget {
  const AliraShopApp({super.key});

  @override
  State<AliraShopApp> createState() => _AliraShopAppState();
}

enum _ShopPage { catalog, cart, form, done }

class _AliraShopAppState extends State<AliraShopApp> {
  final _mock = AliraMock.instance;
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final Map<String, int> _cart = {};

  _ShopPage _page = _ShopPage.catalog;
  AliraOrder? _order;
  String? _error;
  String? _familyId;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadShelf();
  }

  Future<void> _loadShelf() async {
    await AliraCatalog.load(agent: false);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<AliraProduct> get _shelf {
    final family = _familyId;
    return AliraCatalog.products.where((item) {
      if (family != null && item.categoryId != family) return false;
      final query = _search.text.trim();
      return query.isEmpty || item.name.contains(query);
    }).toList();
  }

  AliraProduct? _productById(String id) {
    for (final product in AliraCatalog.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  int get _count => _cart.values.fold(0, (sum, qty) => sum + qty);

  int get _total {
    var total = 0;
    for (final entry in _cart.entries) {
      final product = _productById(entry.key);
      if (product == null) continue;
      total += product.price * entry.value;
    }
    return total;
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (_sending) return;
    if (_name.text.trim().isEmpty ||
        _address.text.trim().isEmpty ||
        phone.length < 10 ||
        _count == 0) {
      setState(() {
        _error = 'أدخل الاسم والعنوان ورقم هاتف مكتمل، مع مواد في السلة.';
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final AliraOrder order;
      if (AliraCatalog.fromServer) {
        final lines = _storeLines();
        final number = await AliraStoreOrders.guest(
          name: _name.text.trim(),
          phone: phone,
          address: _address.text.trim(),
          lines: lines,
        );
        order = AliraOrder(
          id: number,
          status: 'pending',
          customer: {
            'name': _name.text.trim(),
            'address': _address.text.trim(),
            'phone': phone,
          },
          items: [
            for (final entry in _cart.entries)
              {'productId': entry.key, 'quantity': entry.value},
          ],
          notes: AliraStoreOrders.lastQueued
              ? 'انقطع الاتصال. حُفظ الطلب على هذه الحاسبة وسيُرسل عند عودة الإنترنت.'
              : null,
          total: _total,
          currency: 'IQD',
          createdAt: DateTime.now().toIso8601String(),
        );
      } else {
        order = _mock.createOrder(
          name: _name.text.trim(),
          address: _address.text.trim(),
          phone: phone,
          items: [
            for (final entry in _cart.entries)
              {'productId': entry.key, 'quantity': entry.value},
          ],
        );
      }
      if (!mounted) return;
      setState(() {
        _order = order;
        _cart.clear();
        _error = null;
        _sending = false;
        _page = _ShopPage.done;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error is StateError ? error.message : AliraStoreOrders.message(error);
      });
    }
  }

  List<AliraStoreLine> _storeLines() {
    final lines = <AliraStoreLine>[];
    for (final entry in _cart.entries) {
      final product = _productById(entry.key);
      final variantId = product?.variantId;
      final unitId = product?.unitId;
      if (product == null || variantId == null || unitId == null) {
        throw StateError('تعذر ربط إحدى المواد بطلبات المتجر');
      }
      lines.add(
        AliraStoreLine(
          variantId: variantId,
          unitId: unitId,
          quantity: entry.value,
        ),
      );
    }
    if (lines.isEmpty) {
      throw StateError('أضف مواد إلى السلة');
    }
    return lines;
  }

  void _newOrder() {
    _name.clear();
    _address.clear();
    _phone.clear();
    setState(() {
      _order = null;
      _error = null;
      _page = _ShopPage.catalog;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AliraPhone(
      maxWidth: 430,
      fontFamily: 'Tahoma',
      child: Column(
        children: [
          Expanded(child: _body()),
          if (_page == _ShopPage.catalog) _bar(),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_page) {
      case _ShopPage.catalog:
        return _catalog();
      case _ShopPage.cart:
        return _cartPage();
      case _ShopPage.form:
        return _form();
      case _ShopPage.done:
        return _done();
    }
  }

  Widget _catalog() {
    final products = _shelf;
    return Column(
      children: [
        Container(
          color: AliraColors.paper,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            children: [
              const Row(
                children: [
                  Text('9:41', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  Spacer(),
                  Text('LTE · 57%', style: TextStyle(fontSize: 12, color: AliraColors.muted)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AliraColors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('أ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('المتجر', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(
                          'عنوان السيرفر من إعدادات الحاسبة',
                          style: TextStyle(fontSize: 11, color: AliraColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Text('$_count', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'للزبائن · اختر الكمية ثم أرسل الطلب',
                  style: TextStyle(fontSize: 11, color: AliraColors.muted),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'بحث بالاسم',
              isDense: true,
              filled: true,
              fillColor: AliraColors.paper,
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final family in AliraCatalog.families)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(family.name),
                    selected: _familyId == family.id,
                    side: BorderSide(
                      color: _familyId == family.id ? AliraColors.text : AliraColors.line,
                      width: _familyId == family.id ? 1.8 : 1.4,
                    ),
                    onSelected: (_) => setState(() => _familyId = family.id),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _familyId == null
                  ? const Center(child: Text('اختر عائلة المواد'))
                  : products.isEmpty
                      ? const Center(child: Text('لا توجد مواد في المخزن لهذه العائلة'))
                      : Column(
                          children: [
                            Expanded(
                              child: GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: products.length,
                                itemBuilder: (context, index) => _productCard(products[index]),
                              ),
                            ),
                            ListPagination(
                              page: AliraCatalog.page,
                              hasNextPage: AliraCatalog.hasNext,
                              pageSize: 20,
                              loading: AliraCatalog.loading,
                              onPageChanged: (page) async {
                                await AliraCatalog.openPage(page, agent: false);
                                if (mounted) setState(() {});
                              },
                            ),
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _productCard(AliraProduct product) {
    final qty = _cart[product.id] ?? 0;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AliraColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: const Border.fromBorderSide(AliraColors.frame),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _thumb(product)),
          const SizedBox(height: 6),
          Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text('IQD ${aliraMoney(product.price)} · ${product.unit}', style: const TextStyle(fontSize: 11, color: AliraColors.muted)),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: qty == 0
                    ? null
                    : () => setState(() {
                          if (qty <= 1) {
                            _cart.remove(product.id);
                          } else {
                            _cart[product.id] = qty - 1;
                          }
                        }),
                icon: const Icon(Icons.remove, size: 18),
              ),
              Text('$qty'),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _cart[product.id] = qty + 1),
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb(AliraProduct product) {
    return aliraProductImage(
      product.imageUrl,
      fallback: Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _parseColor(product.color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        product.name.split(' ').first,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ),
    );
  }

  Widget _bar() {
    return Material(
      color: AliraColors.paper,
      child: InkWell(
        onTap: () => setState(() => _page = _ShopPage.cart),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text('السلة · IQD ${aliraMoney(_total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _cartPage() {
    final lines = _cart.entries.toList();
    return Column(
      children: [
        AliraStatusBar(title: 'السلة', onBack: () => setState(() => _page = _ShopPage.catalog)),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('السلة فارغة'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final entry in lines)
                      Builder(builder: (context) {
                        final product = _productById(entry.key);
                        if (product == null) return const SizedBox.shrink();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(product.name),
                          subtitle: Text('${entry.value} × IQD ${aliraMoney(product.price)}'),
                          trailing: Text('IQD ${aliraMoney(product.price * entry.value)}'),
                        );
                      }),
                    Text('عدد القطع $_count'),
                    Text('المجموع IQD ${aliraMoney(_total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _count == 0 ? null : () => setState(() => _page = _ShopPage.form),
            child: const Text('إرسال'),
          ),
        ),
      ],
    );
  }

  Widget _form() {
    return Column(
      children: [
        AliraStatusBar(title: 'بيانات الطلب', onBack: () => setState(() => _page = _ShopPage.cart)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'اسم الزبون', filled: true, fillColor: AliraColors.paper),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'العنوان', filled: true, fillColor: AliraColors.paper),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الهاتف', filled: true, fillColor: AliraColors.paper),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: AliraColors.red)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _submit,
            child: const Text('إرسال الطلب'),
          ),
        ),
      ],
    );
  }

  Widget _done() {
    final order = _order!;
    final name = order.customer['name'] ?? '';
    final address = order.customer['address'] ?? '';
    final phone = order.customer['phone'] ?? '';
    return Column(
      children: [
        const AliraStatusBar(title: 'وصل طلبك'),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              order.notes == null
                  ? 'شكراً $name. رقم الطلب ${order.id} بقيمة IQD ${aliraMoney(order.total)} سيُرسل إلى $address. سنتواصل على $phone.'
                  : '${order.notes}\nشكراً $name. الطلب محفوظ على هذه الحاسبة بقيمة IQD ${aliraMoney(order.total)}.',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(onPressed: _newOrder, child: const Text('طلب جديد')),
        ),
      ],
    );
  }

  Color _parseColor(String hex) {
    final value = hex.replaceFirst('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }
}

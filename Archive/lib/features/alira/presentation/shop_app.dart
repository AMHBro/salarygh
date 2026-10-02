import 'package:flutter/material.dart';

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
    try {
      await AliraCatalog.load(
        agent: false,
        query: _search.text,
        familyId: _search.text.trim().isEmpty ? _familyId : null,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } on ServerConnectionException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  void _scheduleShelf() {
    AliraCatalog.scheduleLoad(
      agent: false,
      query: _search.text,
      familyId: _search.text.trim().isEmpty ? _familyId : null,
      onDone: () {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = AliraCatalog.connectionError;
        });
      },
    );
  }

  Future<void> _loadMore() async {
    await AliraCatalog.load(agent: false, append: true);
    if (mounted) setState(() {});
  }

  List<AliraProduct> get _shelf {
    return AliraCatalog.visible(
      familyId: _search.text.trim().isEmpty ? _familyId : null,
      query: _search.text,
    );
  }

  AliraProduct? _productById(String id) => AliraCatalog.byId(id);

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    AliraCatalog.cancelPending();
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
          if (_page == _ShopPage.catalog && AliraCatalog.hasNext) _loadMoreBar(),
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
        const AliraStatusBar(title: 'المتجر', hint: 'سعر المفرد'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _search,
            onChanged: (value) {
              setState(() {
                if (value.trim().isNotEmpty) _familyId = null;
              });
              _scheduleShelf();
            },
            decoration: const InputDecoration(
              hintText: 'ابحث بالاسم',
              isDense: true,
              filled: true,
              fillColor: AliraColors.paper,
              prefixIcon: Icon(Icons.search, size: 20, color: AliraColors.teal),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              _error!,
              style: const TextStyle(color: AliraColors.red, fontWeight: FontWeight.w700),
            ),
          ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            children: [
              AliraFilterChip(
                label: 'الكل',
                selected: _familyId == null,
                onTap: () {
                  setState(() => _familyId = null);
                  _loadShelf();
                },
              ),
              for (final family in AliraCatalog.families)
                AliraFilterChip(
                  label: family.name,
                  selected: _familyId == family.id,
                  onTap: () {
                    setState(() {
                      _familyId = _familyId == family.id ? null : family.id;
                      if (_familyId != null) _search.clear();
                    });
                    _loadShelf();
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : products.isEmpty
                  ? Center(
                      child: Text(
                        _search.text.trim().isEmpty
                            ? 'لا توجد مواد في هذه العائلة'
                            : 'لا توجد مادة بهذا الاسم',
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.58,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) => _productCard(products[index]),
                    ),
        ),
      ],
    );
  }

  void _setQty(String id, int next) {
    setState(() {
      if (next <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = next;
      }
    });
  }

  Widget _productCard(AliraProduct product) {
    final qty = _cart[product.id] ?? 0;
    return AliraSoftCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _thumb(product)),
          const SizedBox(height: 8),
          Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(
            product.categoryName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AliraColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            '${aliraMoney(product.price)} د.ع',
            style: const TextStyle(fontWeight: FontWeight.w800, color: AliraColors.teal),
          ),
          const SizedBox(height: 8),
          if (qty == 0)
            SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: () => _setQty(product.id, 1),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(36), padding: EdgeInsets.zero),
                child: const Text('إضافة'),
              ),
            )
          else
            Align(
              alignment: Alignment.center,
              child: AliraQtyCapsule(
                quantity: qty,
                onMinus: () => _setQty(product.id, qty - 1),
                onPlus: () => _setQty(product.id, qty + 1),
              ),
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

  Widget _loadMoreBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: OutlinedButton(
        onPressed: AliraCatalog.loading ? null : _loadMore,
        child: Text(AliraCatalog.loading ? 'جارٍ التحميل...' : 'تحميل المزيد'),
      ),
    );
  }

  Widget _bar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        color: AliraColors.paper,
        boxShadow: [BoxShadow(color: Color(0x140F4C45), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('$_count مواد', style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${aliraMoney(_total)} د.ع', style: const TextStyle(fontWeight: FontWeight.w800, color: AliraColors.teal)),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _count == 0 ? null : () => setState(() => _page = _ShopPage.cart),
            child: const Text('مراجعة وإرسال الطلب'),
          ),
        ],
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
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AliraSoftCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text('${aliraMoney(product.price)} د.ع', style: const TextStyle(color: AliraColors.muted, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                AliraQtyCapsule(
                                  quantity: entry.value,
                                  onMinus: () => _setQty(product.id, entry.value - 1),
                                  onPlus: () => _setQty(product.id, entry.value + 1),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    AliraSoftCard(
                      child: Row(
                        children: [
                          Text('$_count مواد'),
                          const Spacer(),
                          Text('${aliraMoney(_total)} د.ع', style: const TextStyle(fontWeight: FontWeight.w800, color: AliraColors.teal)),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _count == 0 ? null : () => setState(() => _page = _ShopPage.form),
            child: const Text('متابعة البيانات'),
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
              _fieldCard(_name, 'الاسم'),
              const SizedBox(height: 10),
              _fieldCard(_phone, 'الهاتف', type: TextInputType.phone),
              const SizedBox(height: 10),
              _fieldCard(_address, 'العنوان'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: AliraColors.red, fontWeight: FontWeight.w700)),
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

  Widget _fieldCard(TextEditingController controller, String label, {TextInputType? type}) {
    return AliraSoftCard(
      child: TextField(
        controller: controller,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    final value = hex.replaceFirst('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }
}

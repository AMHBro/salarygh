import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../warehouses/models/warehouse_model.dart';
import '../data/station_grants.dart';

class StationsScreen extends StatefulWidget {
  const StationsScreen({super.key});

  @override
  State<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends State<StationsScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;
  List<_RoleChoice> _roles = const [];
  String? _roleId;
  List<_Station> _stations = const [];
  List<WarehouseModel> _warehouses = const [];
  Map<String, String> _grants = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rolesResponse = await AppServices.apiClient.get('/users/roles');
      final usersResponse = await AppServices.apiClient.get('/users');
      final roles = <_RoleChoice>[];
      final rawRoles = rolesResponse.data;
      if (rawRoles is List) {
        for (final row in rawRoles) {
          if (row is Map) {
            roles.add(_RoleChoice.fromJson(Map<String, dynamic>.from(row)));
          }
        }
      }
      final stations = <_Station>[];
      final rawUsers = usersResponse.data;
      if (rawUsers is List) {
        for (final row in rawUsers) {
          if (row is Map) {
            stations.add(_Station.fromJson(Map<String, dynamic>.from(row)));
          }
        }
      }
      final grants = await StationGrants.read();
      final warehouses = await AppServices.warehousesRepository.getWarehouses();
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _roleId ??= roles.isEmpty ? null : roles.first.id;
        _stations = stations;
        _grants = grants;
        _warehouses = warehouses
            .where(
              (warehouse) =>
                  warehouse.isActive &&
                  warehouse.deletedAt == null &&
                  (warehouse.serverId ?? '').trim().isNotEmpty,
            )
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final username = _username.text.trim();
    final password = _password.text;
    if (name.isEmpty || username.isEmpty || password.length < 6 || _roleId == null) {
      setState(() {
        _error = 'اكتب الاسم واسم الدخول وكلمة مرور من 6 أحرف، واختر الصلاحية.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await AppServices.apiClient.post(
        '/users',
        data: {
          'full_name': name,
          'username': username,
          'password': password,
          'email': '$username@station.sayler.app',
          'role_id': _roleId,
        },
      );
      _name.clear();
      _username.clear();
      _password.clear();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = 'حُفظ الدخول. على الحاسبة الأخرى سجّل بالاسم $username وكلمة المرور التي كتبتها.';
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _setRole(_Station station, String? roleId) async {
    if (roleId == null || roleId == station.roleId) return;
    try {
      await AppServices.apiClient.patch(
        '/users/${station.id}',
        data: {'role_id': roleId},
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    }
  }

  Future<void> _setWarehouse(_Station station, String? serverId) async {
    try {
      await StationGrants.save(station.id, serverId);
      if (!mounted) return;
      setState(() {
        _grants = {
          ..._grants,
          if ((serverId ?? '').trim().isNotEmpty) station.id: serverId!.trim(),
        };
        if ((serverId ?? '').trim().isEmpty) {
          _grants.remove(station.id);
        }
        _notice = 'صار دخول ${station.name} على المخزن الذي اخترته. البيع والشراء يظهران هنا بعد المزامنة.';
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    }
  }

  Future<void> _delete(_Station station) async {
    final session = await AppServices.authStorage.readSession();
    if (session?.user.id == station.id) {
      setState(() => _error = 'لا يمكن حذف الحساب الذي دخلت به.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('حذف الحاسبة'),
            content: Text('حذف دخول «${station.name}»؟ لن يستطيع فتح النظام بهذا الحساب.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await StationGrants.save(station.id, null);
      await AppServices.apiClient.delete('/users/${station.id}');
      if (!mounted) return;
      setState(() {
        _notice = 'حُذفت الحاسبة ${station.name}.';
        _error = null;
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    }
  }

  Future<void> _toggle(_Station station) async {
    try {
      await AppServices.apiClient.patch(
        '/users/${station.id}',
        data: {'is_active': !station.active},
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    }
  }

  String? _grantValue(String userId) {
    final serverId = _grants[userId]?.trim() ?? '';
    if (serverId.isEmpty) return '';
    for (final warehouse in _warehouses) {
      if (warehouse.serverId == serverId) return serverId;
    }
    return '';
  }

  String _message(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 403) {
        return 'إعطاء الصلاحيات وبيانات الدخول للمسؤول فقط.';
      }
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        final message = data['message'];
        if (message is List && message.isNotEmpty) return '${message.first}';
        return '$message';
      }
    }
    return 'تعذر حفظ بيانات الحاسبة.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الحاسبات والصلاحيات',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'لكل حاسبة اسم دخول وكلمة مرور. المسؤول يعيّن مخزناً واحداً، والحاسبة البعيدة تبيع وتشتري عليه فقط. عملياتها تظهر في خانة المسؤول وفي الكشوفات بعد المزامنة.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 16),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'اسم صاحب الحاسبة'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _username,
          decoration: const InputDecoration(labelText: 'اسم الدخول'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'كلمة المرور'),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _roleId,
          decoration: const InputDecoration(labelText: 'الصلاحية'),
          items: [
            for (final role in _roles)
              DropdownMenuItem(
                value: role.id,
                child: Text('${role.title} — ${role.detail}'),
              ),
          ],
          onChanged: (value) => setState(() => _roleId = value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving ? null : _create,
            child: Text(_saving ? 'جارٍ الحفظ' : 'حفظ دخول الحاسبة'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: AppTheme.dangerColor)),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 8),
          Text(_notice!, style: const TextStyle(color: AppTheme.successColor)),
        ],
        const SizedBox(height: 20),
        if (_warehouses.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'لا يوجد مخزن متزامن بعد. من المنتجات اضغط مزامنة الآن، ثم ارجع لهذه الصفحة لتعيين المخزن.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
          ),
        for (final station in _stations) ...[
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(station.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('الدخول: ${station.username} · ${station.roleTitle(_roles)}'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      DropdownButton<String>(
                        value: station.roleId,
                        items: [
                          for (final role in _roles)
                            DropdownMenuItem(value: role.id, child: Text(role.title)),
                        ],
                        onChanged: (value) => _setRole(station, value),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => _toggle(station),
                        child: Text(station.active ? 'إيقاف' : 'تفعيل'),
                      ),
                      TextButton(
                        onPressed: () => _delete(station),
                        child: const Text(
                          'حذف',
                          style: TextStyle(color: AppTheme.dangerColor),
                        ),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('${station.id}-${_grantValue(station.id)}'),
                    initialValue: _grantValue(station.id),
                    decoration: const InputDecoration(labelText: 'المخزن المسموح'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('بدون مخزن')),
                      for (final warehouse in _warehouses)
                        DropdownMenuItem(
                          value: warehouse.serverId,
                          child: Text(warehouse.name),
                        ),
                    ],
                    onChanged: (value) => _setWarehouse(
                      station,
                      value == null || value.isEmpty ? null : value,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RoleChoice {
  final String id;
  final String title;
  final String detail;

  const _RoleChoice({
    required this.id,
    required this.title,
    required this.detail,
  });

  factory _RoleChoice.fromJson(Map<String, dynamic> json) {
    return _RoleChoice(
      id: '${json['id']}',
      title: '${json['title'] ?? json['name'] ?? ''}',
      detail: '${json['detail'] ?? ''}',
    );
  }
}

class _Station {
  final String id;
  final String name;
  final String username;
  final String? roleId;
  final String? roleName;
  final bool active;

  const _Station({
    required this.id,
    required this.name,
    required this.username,
    required this.roleId,
    required this.roleName,
    required this.active,
  });

  factory _Station.fromJson(Map<String, dynamic> json) {
    final roleId = '${json['role_id'] ?? ''}'.trim();
    return _Station(
      id: '${json['id']}',
      name: '${json['full_name'] ?? json['username'] ?? ''}',
      username: '${json['username'] ?? ''}',
      roleId: roleId.isEmpty ? null : roleId,
      roleName: '${json['role_name'] ?? ''}',
      active: json['is_active'] != false,
    );
  }

  String roleTitle(List<_RoleChoice> roles) {
    for (final role in roles) {
      if (role.id == roleId) return role.title;
    }
    return roleName ?? 'بدون صلاحية';
  }
}

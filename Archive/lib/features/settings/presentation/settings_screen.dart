import 'package:flutter/material.dart';

import '../../../core/backup/local_backup.dart';
import '../../../core/di/app_services.dart';
import '../../../core/network/server_endpoint.dart';
import '../../../core/theme/app_theme.dart';
import '../data/company_settings_repository.dart';
import '../models/document_layout.dart';
import 'document_layout_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repository = CompanySettingsRepository(
    apiClient: AppServices.apiClient,
  );

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxController = TextEditingController();
  final _rateController = TextEditingController();
  final _capitalController = TextEditingController();
  final _lanController = TextEditingController();
  final _internetController = TextEditingController();

  Map<String, dynamic> _settings = {};
  List<LayoutBlock> _invoiceLayout =
      List<LayoutBlock>.from(DocumentLayouts.invoiceDefaults);
  List<LayoutBlock> _receiptLayout =
      List<LayoutBlock>.from(DocumentLayouts.receiptDefaults);
  DocumentHeader _documentHeader = const DocumentHeader();
  bool _loading = true;
  bool _saving = false;
  bool _backupBusy = false;
  bool _serverSaving = false;
  bool _useInternet = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _taxController.dispose();
    _rateController.dispose();
    _capitalController.dispose();
    _lanController.dispose();
    _internetController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await _loadServer();

    try {
      final company = await _repository.getCompany();

      if (!mounted) {
        return;
      }

      final settings = company['settings'];
      _settings = settings is Map
          ? Map<String, dynamic>.from(settings)
          : <String, dynamic>{};

      _nameController.text = '${company['name'] ?? ''}';
      _phoneController.text = '${company['phone'] ?? ''}';
      _emailController.text = '${company['email'] ?? ''}';
      _addressController.text = '${company['address'] ?? ''}';
      _taxController.text = '${company['tax_number'] ?? ''}';
      _rateController.text = '${_settings['usd_exchange_rate'] ?? ''}';
      _capitalController.text = '${_settings['opening_capital'] ?? ''}';
      _invoiceLayout = DocumentLayouts.invoiceFrom(_settings);
      _receiptLayout = DocumentLayouts.receiptFrom(_settings);
      _documentHeader = DocumentLayouts.headerFrom(_settings);

      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _loadServer() async {
    final route = await ServerEndpoint.instance.read();
    if (!mounted) return;
    _lanController.text = route.lanBase;
    _internetController.text = route.internetBase ?? '';
    _useInternet = route.useInternet;
  }

  Future<void> _saveServer() async {
    setState(() {
      _serverSaving = true;
      _error = null;
      _notice = null;
    });
    try {
      await ServerEndpoint.instance.save(
        ServerRoute(
          useInternet: _useInternet,
          lanBase: _lanController.text,
          internetBase: _internetController.text,
        ),
      );
      if (!mounted) return;
      final route = await ServerEndpoint.instance.read();
      setState(() {
        _serverSaving = false;
        _lanController.text = route.lanBase;
        _internetController.text = route.internetBase ?? '';
        _notice = _useInternet
            ? 'هذه الحاسبة تتصل عبر الإنترنت. إذا انقطع الاتصال يبقى العمل محفوظاً ويُرسل عند عودته.'
            : 'هذه الحاسبة تتصل عبر الراوتر. تبقى على السيرفر المحلي إذا انقطع الإنترنت.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverSaving = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _error = 'اسم الشركة مطلوب.';
        _notice = null;
      });
      return;
    }

    final settings = Map<String, dynamic>.from(_settings);
    final rate = _rateController.text.trim();

    if (rate.isEmpty) {
      settings.remove('usd_exchange_rate');
    } else {
      settings['usd_exchange_rate'] = rate;
    }

    final capital = _capitalController.text.trim().replaceAll(',', '');
    if (capital.isEmpty) {
      settings.remove('opening_capital');
    } else {
      settings['opening_capital'] = capital;
    }

    settings['document_layouts'] = DocumentLayouts.toSettings(
      invoice: _invoiceLayout,
      receipt: _receiptLayout,
      header: _documentHeader,
    );

    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });

    try {
      await _repository.updateCompany({
        'name': name,
        'phone': _emptyToNull(_phoneController.text),
        'email': _emptyToNull(_emailController.text),
        'address': _emptyToNull(_addressController.text),
        'tax_number': _emptyToNull(_taxController.text),
        'settings': settings,
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _settings = settings;
        _saving = false;
        _notice = 'تم حفظ إعدادات الشركة.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _exportBackup() async {
    setState(() {
      _backupBusy = true;
      _error = null;
      _notice = null;
    });
    try {
      final count = await LocalBackup(database: AppServices.database).exportFile();
      if (!mounted) {
        return;
      }
      setState(() {
        _backupBusy = false;
        _notice = 'تم تنزيل النسخة الاحتياطية. عدد السجلات: $count.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _backupBusy = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('استرجاع النسخة'),
            content: const Text(
              'سيُستبدل كل ما على هذه الحاسبة من مبيعات ومشتريات وزبائن ومخزون ببيانات ملف النسخة.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('استرجاع'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _backupBusy = true;
      _error = null;
      _notice = null;
    });
    try {
      final count = await LocalBackup(database: AppServices.database).restoreFromFile();
      if (!mounted) {
        return;
      }
      setState(() {
        _backupBusy = false;
        _notice = count == null
            ? 'لم يُختر ملف.'
            : 'تم الاسترجاع. عدد السجلات: $count. حدّث الصفحة لترى البيانات.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _backupBusy = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  String? _emptyToNull(String value) {
    final clean = value.trim();
    return clean.isEmpty ? null : clean;
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
              'الإعدادات',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'اسم الشركة والشعار وسعر الدولار ورأس المال وترتيب القوائم تُحفظ على السيرفر، وكل حاسبة تسحبها منه.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Align(
      alignment: Alignment.topRight,
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          children: [
            const Text(
              'اتصال الحاسبات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'الحاسوبان على الراوتر يختاران «على الراوتر» ويكتبان عنوان السيرفر داخل الشبكة. الحاسبة البعيدة والمتجر والمندوب يختاران «عبر الإنترنت». إذا انقطع الإنترنت يبقى البيع والشراء محفوظين على الحاسبة، ثم يُرسلان تلقائياً عند عودة الاتصال.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('على الراوتر'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('عبر الإنترنت'),
                ),
              ],
              selected: {_useInternet},
              onSelectionChanged: (value) {
                setState(() => _useInternet = value.first);
              },
            ),
            const SizedBox(height: 8),
            Text(
              _useInternet
                  ? 'للحاسبة البعيدة والمتجر والمندوب. العمل يبقى محفوظاً ويُرسل عند عودة الإنترنت.'
                  : 'للحاسوبين داخل الشبكة. يبقى الاتصال بالسيرفر إذا انقطع الإنترنت.',
              style: const TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 12),
            _field(
              _lanController,
              'عنوان السيرفر على الراوتر',
              hint: '192.168.1.8:3000',
            ),
            _field(
              _internetController,
              'عنوان السيرفر عبر الإنترنت',
              hint: 'https://example.com',
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _serverSaving ? null : _saveServer,
                child: Text(_serverSaving ? 'جارٍ الحفظ' : 'حفظ عنوان هذه الحاسبة'),
              ),
            ),
            const SizedBox(height: 24),
            _field(_nameController, 'اسم الشركة'),
            _field(_phoneController, 'الهاتف'),
            _field(_emailController, 'البريد'),
            _field(_addressController, 'العنوان'),
            _field(_taxController, 'الرقم الضريبي'),
            _field(
              _rateController,
              'سعر صرف الدولار',
              hint: 'يحوّل بيع وشراء الدولار إلى دينار في الكشوفات',
            ),
            _field(
              _capitalController,
              'رأس المال',
              hint: 'المبلغ الذي تبدأ به. البيع يضيف الربح، والشراء والقبض والصرف لا يغيرونه',
            ),
            const SizedBox(height: 8),
            DocumentLayoutSection(
              invoice: _invoiceLayout,
              receipt: _receiptLayout,
              header: _documentHeader,
              onInvoiceChanged: (value) {
                setState(() {
                  _invoiceLayout = value;
                });
              },
              onReceiptChanged: (value) {
                setState(() {
                  _receiptLayout = value;
                });
              },
              onHeaderChanged: (value) {
                _documentHeader = value;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.dangerColor),
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 8),
              Text(
                _notice!,
                style: const TextStyle(color: AppTheme.successColor),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'نسخة هذه الحاسبة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'هذا الملف نسخة SQLite لهذه الحاسبة فقط، بما فيها فواتير لم تُرفع بعد. لا يشمل حاسبات المكتب الأخرى ولا قاعدة الخادم. نسخة المكتب تُؤخذ على جهاز الخادم بالأمر npm run db:backup.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _backupBusy ? null : _exportBackup,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('تنزيل نسخة'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _backupBusy ? null : _restoreBackup,
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: const Text('رفع النسخة واسترجاعها'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'جارٍ الحفظ' : 'حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/backup/local_backup.dart';
import '../../../core/di/app_services.dart';
import '../../../core/lan/office_role.dart';
import '../../../core/network/server_endpoint.dart';
import '../../../core/theme/app_theme.dart';
import '../data/company_settings_repository.dart';
import '../data/print_settings_store.dart';
import '../models/document_layout.dart';
import '../models/print_settings.dart';
import '../models/public_links.dart';
import 'document_layout_section.dart';
import 'print_template_section.dart';

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
  final _lanMasterController = TextEditingController();
  final _lanTokenController = TextEditingController();
  final _shopLinkController = TextEditingController(text: PublicLinks.shop);
  final _agentLinkController = TextEditingController(text: PublicLinks.agent);
  final _photosLinkController = TextEditingController(text: PublicLinks.photos);
  final _followLinkController = TextEditingController(text: PublicLinks.follow);

  Map<String, dynamic> _settings = {};
  List<LayoutBlock> _invoiceLayout =
      List<LayoutBlock>.from(DocumentLayouts.invoiceDefaults);
  List<LayoutBlock> _receiptLayout =
      List<LayoutBlock>.from(DocumentLayouts.receiptDefaults);
  DocumentHeader _documentHeader = const DocumentHeader();
  PrintSettings _printSettings = const PrintSettings();
  bool _loading = true;
  bool _saving = false;
  bool _backupBusy = false;
  bool _serverSaving = false;
  bool _useInternet = false;
  bool _branchOffice = false;
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
    _lanMasterController.dispose();
    _lanTokenController.dispose();
    _shopLinkController.dispose();
    _agentLinkController.dispose();
    _photosLinkController.dispose();
    _followLinkController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await _loadServer();
    try {
      _printSettings = await PrintSettingsStore(AppServices.database).read();
    } catch (_) {
      _printSettings = const PrintSettings();
    }

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
      final links = PublicLinks.fromSettings(_settings);
      _shopLinkController.text = links.shopUrl;
      _agentLinkController.text = links.agentUrl;
      _photosLinkController.text = links.photosUrl;
      _followLinkController.text = links.followUrl;

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
    _branchOffice = await OfficeRole.instance.isBranch();
    _lanMasterController.text = await OfficeRole.instance.readBase();
    _lanTokenController.text = await OfficeRole.instance.readToken();
    if (!mounted) return;
    setState(() {});
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
      await OfficeRole.instance.save(
        branchOffice: _branchOffice,
        baseUrl: _lanMasterController.text,
        token: _lanTokenController.text,
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
    try {
      await PrintSettingsStore(AppServices.database).save(_printSettings);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _notice = null;
      });
      return;
    }

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

    late final PublicLinks links;
    try {
      links = PublicLinks(
        shopUrl: _requiredLink(_shopLinkController.text, PublicLinks.shop),
        agentUrl: _requiredLink(_agentLinkController.text, PublicLinks.agent),
        photosUrl: _requiredLink(_photosLinkController.text, PublicLinks.photos),
        followUrl: _requiredLink(_followLinkController.text, PublicLinks.follow),
      );
    } on StateError catch (error) {
      setState(() {
        _error = error.message;
        _notice = null;
      });
      return;
    }
    settings['public_links'] = links.toSettings();

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
        _shopLinkController.text = links.shopUrl;
        _agentLinkController.text = links.agentUrl;
        _photosLinkController.text = links.photosUrl;
        _followLinkController.text = links.followUrl;
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
        _notice = count == null
            ? 'أُلغي حفظ النسخة.'
            : 'حُفظت النسخة على الجهاز. عدد السجلات: $count.';
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
            : 'تم الاسترجاع. عدد السجلات: $count. أغلق النظام وافتحه من جديد لترى البيانات.';
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
              hint: ServerEndpoint.defaultInternet,
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('حاسبة أساسية'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('حاسبة فرعية'),
                ),
              ],
              selected: {_branchOffice},
              onSelectionChanged: (value) {
                setState(() => _branchOffice = value.first);
              },
            ),
            const SizedBox(height: 8),
            Text(
              _branchOffice
                  ? 'الفاتورة تُرسل إلى الحاسبة الأساسية ولا يُفتح ملفها من هنا.'
                  : 'هذه الحاسبة تعالج طابور الفروع على ملفها المحلي.',
              style: const TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 8),
            _field(
              _lanMasterController,
              'عنوان خادم الحاسبة الأساسية',
              hint: 'http://192.168.1.8:3920',
            ),
            _field(
              _lanTokenController,
              'رمز الشبكة المحلية',
              hint: 'يُضبط على الحاسبة الأساسية في LAN_TOKEN',
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
            const Text(
              'الروابط',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'روابط المتجر والمندوب ورفع الصور ومتابعة المدير. رابط المتجر يُطبع كرمز على الفاتورة. اضغط حفظ في الأسفل لتثبيتها.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 12),
            _linkField(_shopLinkController, 'رابط المتجر'),
            _linkField(_agentLinkController, 'رابط المندوب'),
            _linkField(_photosLinkController, 'رابط رفع الصور'),
            _linkField(_followLinkController, 'رابط متابعة المدير'),
            const SizedBox(height: 12),
            PrintTemplateSection(
              settings: _printSettings,
              storeUrl: _shopLinkController.text.trim().isEmpty
                  ? PublicLinks.shop
                  : _shopLinkController.text.trim(),
              onChanged: (value) {
                setState(() {
                  _printSettings = value;
                });
              },
            ),
            const SizedBox(height: 18),
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
              'يحفظ ملف هذه الحاسبة على الجهاز، بما فيها فواتير لم تُرفع بعد. لا يشمل حاسبات المكتب الأخرى ولا قاعدة الخادم.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _backupBusy ? null : _exportBackup,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('حفظ نسخة'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _backupBusy ? null : _restoreBackup,
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: const Text('استرجاع من ملف'),
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

  String _requiredLink(String raw, String fallback) {
    final text = raw.trim();
    if (text.isEmpty) return fallback;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw StateError('الرابط يجب أن يبدأ بـ https://');
    }
    return text;
  }

  Widget _linkField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            tooltip: 'نسخ',
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              await Clipboard.setData(ClipboardData(text: value));
              if (!mounted) return;
              setState(() => _notice = 'تم نسخ الرابط.');
            },
            icon: const Icon(Icons.copy_outlined),
          ),
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

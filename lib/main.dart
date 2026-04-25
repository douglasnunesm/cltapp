import 'dart:convert';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String admobBannerUnitId = 'ca-app-pub-5979475974508131/7828121452';

enum AppSection { calculators, history, settings }

enum CalcTab { salary, vacation, termination }

enum TerminationType { withoutCause, employeeResignation, withCause }

class HistoryEntry {
  final String type;
  final String title;
  final double amount;
  final String detail;
  final String createdAt;

  HistoryEntry({
    required this.type,
    required this.title,
    required this.amount,
    required this.detail,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'amount': amount,
    'detail': detail,
    'createdAt': createdAt,
  };

  static HistoryEntry fromJson(Map<String, dynamic> json) => HistoryEntry(
    type: json['type'] ?? '',
    title: json['title'] ?? '',
    amount: (json['amount'] ?? 0).toDouble(),
    detail: json['detail'] ?? '',
    createdAt: json['createdAt'] ?? '',
  );
}

class PtBrCurrencyInputFormatter extends TextInputFormatter {
  const PtBrCurrencyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.replaceAll(RegExp(r'[^0-9,\.]'), '');
    if (cleaned.isEmpty) {
      return const TextEditingValue(text: '');
    }

    int separatorIndex = -1;
    for (var i = 0; i < cleaned.length; i++) {
      final ch = cleaned[i];
      if (ch == ',' || ch == '.') {
        separatorIndex = i;
        break;
      }
    }

    var integerPart =
        separatorIndex >= 0
            ? cleaned
                .substring(0, separatorIndex)
                .replaceAll(RegExp(r'[^0-9]'), '')
            : cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    final decimalPartRaw =
        separatorIndex >= 0
            ? cleaned
                .substring(separatorIndex + 1)
                .replaceAll(RegExp(r'[^0-9]'), '')
            : '';

    if (integerPart.isEmpty && separatorIndex < 0) {
      return const TextEditingValue(text: '');
    }

    if (integerPart.isEmpty) {
      integerPart = '0';
    }
    integerPart = integerPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (integerPart.isEmpty) {
      integerPart = '0';
    }

    final withThousands = integerPart.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    final limitedDecimal =
        decimalPartRaw.length > 2
            ? decimalPartRaw.substring(0, 2)
            : decimalPartRaw;
    final hasDecimalSeparator = separatorIndex >= 0;
    final formatted =
        hasDecimalSeparator ? '$withThousands,$limitedDecimal' : withThousands;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeTelemetry();
  runApp(const CltFlutterApp());
}

Future<void> _initializeTelemetry() async {
  if (!kIsWeb) {
    await MobileAds.instance.initialize();
  }

  try {
    await Firebase.initializeApp();
    if (!kIsWeb) {
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    }
  } catch (error) {
    debugPrint('Firebase nao inicializado: $error');
  }
}

class CltFlutterApp extends StatefulWidget {
  const CltFlutterApp({super.key});

  @override
  State<CltFlutterApp> createState() => _CltFlutterAppState();
}

class _CltFlutterAppState extends State<CltFlutterApp> {
  final NumberFormat brl = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  FirebaseAnalytics? _analytics;

  AppSection section = AppSection.calculators;
  CalcTab calcTab = CalcTab.salary;
  TerminationType terminationType = TerminationType.withoutCause;

  bool darkMode = false;
  bool salarySimplified = true;
  bool vacationSimplified = true;
  bool vacationAdvance13 = false;
  bool terminationSimplified = true;
  bool employerNoticeIndemnified = true;
  bool discountEmployeeNotice = false;

  String salaryInput = '';
  String vacationSalaryInput = '';
  String vacationDaysInput = '30';
  String vacationOvertimeInput = '0,00';
  String vacationDependentsInput = '0';

  String terminationSalaryInput = '';
  String terminationDaysInput = '30';
  String termination13Input = '12';
  String terminationVacationDueInput = '0';
  String terminationVacationPropInput = '0';
  String terminationFgtsInput = '0,00';
  String terminationDependentsInput = '0';

  String? salaryError;
  String? vacationError;
  String? terminationError;

  Map<String, double>? salaryResult;
  Map<String, double>? vacationResult;
  Map<String, double>? terminationResult;

  List<HistoryEntry> history = [];

  BannerAd? _bannerAd;
  bool _isBannerReady = false;

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void initState() {
    super.initState();
    _setupAnalytics();
    _loadState();
    _loadBanner();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      darkMode = prefs.getBool('dark_mode') ?? false;
      salarySimplified = prefs.getBool('salary_simplified') ?? true;
      vacationSimplified = prefs.getBool('vac_simplified') ?? true;
      vacationAdvance13 = prefs.getBool('vac_advance_13') ?? false;
      terminationSimplified = prefs.getBool('term_simplified') ?? true;
      employerNoticeIndemnified =
          prefs.getBool('term_notice_indemnified') ?? true;
      discountEmployeeNotice = prefs.getBool('term_notice_discount') ?? false;

      salaryInput = prefs.getString('salary_input') ?? '';
      vacationSalaryInput = prefs.getString('vac_salary_input') ?? '';
      vacationDaysInput = prefs.getString('vac_days_input') ?? '30';
      vacationOvertimeInput = prefs.getString('vac_overtime_input') ?? '0,00';
      vacationDependentsInput = prefs.getString('vac_dependents_input') ?? '0';

      terminationSalaryInput = prefs.getString('term_salary_input') ?? '';
      terminationDaysInput = prefs.getString('term_days_input') ?? '30';
      termination13Input = prefs.getString('term_m13_input') ?? '12';
      terminationVacationDueInput = prefs.getString('term_due_input') ?? '0';
      terminationVacationPropInput = prefs.getString('term_prop_input') ?? '0';
      terminationFgtsInput = prefs.getString('term_fgts_input') ?? '0,00';
      terminationDependentsInput =
          prefs.getString('term_dependents_input') ?? '0';

      final termRaw = prefs.getString('term_type') ?? 'without_cause';
      terminationType = _terminationTypeFromKey(termRaw);

      final histRaw = prefs.getString('history_items');
      if (histRaw != null) {
        final decoded = jsonDecode(histRaw) as List<dynamic>;
        history =
            decoded
                .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
                .toList();
      }
    });
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(history.map((e) => e.toJson()).toList());
    await prefs.setString('history_items', encoded);
  }

  void _loadBanner() {
    if (kIsWeb) return;

    final ad = BannerAd(
      adUnitId: admobBannerUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() => _isBannerReady = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Erro ao carregar banner: $error');
        },
      ),
    );
    ad.load();
    _bannerAd = ad;
  }

  void _setupAnalytics() {
    try {
      _analytics = FirebaseAnalytics.instance;
      _analytics!.setAnalyticsCollectionEnabled(true);
      _analytics!.logAppOpen();
    } catch (_) {
      _analytics = null;
    }
  }

  Future<void> _logEvent(
    String event, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final analytics = _analytics;
    if (analytics == null) return;

    final payload = <String, Object>{};
    parameters.forEach((key, value) {
      if (value is num || value is String) {
        payload[key] = value as Object;
      } else if (value is bool) {
        payload[key] = value ? 1 : 0;
      } else if (value != null) {
        payload[key] = value.toString();
      }
    });

    try {
      await analytics.logEvent(name: event, parameters: payload);
    } catch (_) {}
  }

  void _setSection(AppSection nextSection) {
    setState(() => section = nextSection);
    _logEvent('menu_section_open', {'section': _sectionKey(nextSection)});
  }

  void _setCalcTab(CalcTab nextTab) {
    setState(() => calcTab = nextTab);
    _logEvent('calculator_tab_open', {'tab': _calcTabKey(nextTab)});
  }

  String _sectionKey(AppSection current) {
    switch (current) {
      case AppSection.calculators:
        return 'calculators';
      case AppSection.history:
        return 'history';
      case AppSection.settings:
        return 'settings';
    }
  }

  String _calcTabKey(CalcTab current) {
    switch (current) {
      case CalcTab.salary:
        return 'salary';
      case CalcTab.vacation:
        return 'vacation';
      case CalcTab.termination:
        return 'termination';
    }
  }

  String _terminationTypeKey(TerminationType current) {
    switch (current) {
      case TerminationType.withoutCause:
        return 'without_cause';
      case TerminationType.employeeResignation:
        return 'employee_resignation';
      case TerminationType.withCause:
        return 'with_cause';
    }
  }

  TerminationType _terminationTypeFromKey(String raw) {
    switch (raw) {
      case 'without_cause':
        return TerminationType.withoutCause;
      case 'employee_resignation':
        return TerminationType.employeeResignation;
      case 'with_cause':
        return TerminationType.withCause;
      default:
        return TerminationType.withoutCause;
    }
  }

  double? _parseMoney(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;

    var normalized = value.replaceAll(RegExp(r'[^0-9,\.]'), '');
    final lastComma = normalized.lastIndexOf(',');
    final lastDot = normalized.lastIndexOf('.');

    if (lastComma >= 0 && lastDot >= 0) {
      if (lastComma > lastDot) {
        normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
      } else {
        normalized = normalized.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else {
      normalized = normalized.replaceAll(',', '');
    }

    return double.tryParse(normalized);
  }

  int _parseIntOr(String input, int fallback) {
    try {
      return int.parse(input);
    } on FormatException {
      return fallback;
    }
  }

  double _mapDouble(
    Map<String, double> values,
    String key, [
    double fallback = 0,
  ]) {
    final dynamic value = values[key];
    return value is double ? value : fallback;
  }

  String _nowLabel() {
    return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
  }

  double _calculateInss(double gross) {
    final capped = gross > 8475.55 ? 8475.55 : gross;
    final brackets = [
      [0.0, 1621.00, 0.075],
      [1621.00, 2902.84, 0.09],
      [2902.84, 4354.27, 0.12],
      [4354.27, 8475.55, 0.14],
    ];

    double total = 0;
    for (final b in brackets) {
      final lower = b[0];
      final upper = b[1];
      final rate = b[2];
      final taxable = (capped.clamp(lower, upper) - lower);
      if (taxable > 0) total += taxable * rate;
    }
    return total;
  }

  String _inssBracketLabel(double grossBase) {
    if (grossBase <= 1621.00) return 'Faixa 1: até R\$ 1.621,00 (7,5%)';
    if (grossBase <= 2902.84) {
      return 'Faixa 2: de R\$ 1.621,01 até R\$ 2.902,84 (9%)';
    }
    if (grossBase <= 4354.27) {
      return 'Faixa 3: de R\$ 2.902,85 até R\$ 4.354,27 (12%)';
    }
    if (grossBase <= 8475.55) {
      return 'Faixa 4: de R\$ 4.354,28 até R\$ 8.475,55 (14%)';
    }
    return 'Acima do teto do INSS (R\$ 8.475,55): contribuição limitada ao teto';
  }

  Map<String, double> _irrfRateAndDeduction(double adjustedBase) {
    if (adjustedBase <= 2428.80) return {'rate': 0, 'deduction': 0};
    if (adjustedBase <= 2826.65) return {'rate': 0.075, 'deduction': 182.16};
    if (adjustedBase <= 3751.05) return {'rate': 0.15, 'deduction': 394.16};
    if (adjustedBase <= 4664.68) return {'rate': 0.225, 'deduction': 675.49};
    return {'rate': 0.275, 'deduction': 908.73};
  }

  String _irrfBracketLabel(double adjustedBase) {
    if (adjustedBase <= 2428.80) {
      return 'Faixa isenta: até R\$ 2.428,80 (0%)';
    }
    if (adjustedBase <= 2826.65) {
      return 'Faixa 7,5%: de R\$ 2.428,81 até R\$ 2.826,65';
    }
    if (adjustedBase <= 3751.05) {
      return 'Faixa 15%: de R\$ 2.826,66 até R\$ 3.751,05';
    }
    if (adjustedBase <= 4664.68) {
      return 'Faixa 22,5%: de R\$ 3.751,06 até R\$ 4.664,68';
    }
    return 'Faixa 27,5%: acima de R\$ 4.664,68';
  }

  String _pct(double value) {
    final pct = value * 100;
    final isInt = pct % 1 == 0;
    return '${pct.toStringAsFixed(isInt ? 0 : 1)}%';
  }

  double _calculateIrrf({
    required double grossForReduction,
    required double taxBase,
    required int dependents,
    required bool applySimplified,
  }) {
    const simplifiedDiscount = 607.20;
    const dependentDeduction = 189.59;

    final baseAfterDeps = (taxBase - (dependents * dependentDeduction)).clamp(
      0,
      double.infinity,
    );
    final adjustedBase =
        applySimplified
            ? (baseAfterDeps - simplifiedDiscount).clamp(0, double.infinity)
            : baseAfterDeps;

    double rate = 0;
    double deduction = 0;
    if (adjustedBase <= 2428.80) {
      rate = 0;
      deduction = 0;
    } else if (adjustedBase <= 2826.65) {
      rate = 0.075;
      deduction = 182.16;
    } else if (adjustedBase <= 3751.05) {
      rate = 0.15;
      deduction = 394.16;
    } else if (adjustedBase <= 4664.68) {
      rate = 0.225;
      deduction = 675.49;
    } else {
      rate = 0.275;
      deduction = 908.73;
    }

    final irrfByTable = (adjustedBase * rate - deduction).clamp(
      0,
      double.infinity,
    );

    double reduction;
    if (grossForReduction <= 5000) {
      reduction = 312.89;
    } else if (grossForReduction <= 7350) {
      reduction = (978.62 - (0.133145 * grossForReduction)).clamp(
        0,
        double.infinity,
      );
    } else {
      reduction = 0;
    }

    return (irrfByTable - reduction).clamp(0, double.infinity);
  }

  void _addHistory(String type, String title, double amount, String detail) {
    setState(() {
      history.insert(
        0,
        HistoryEntry(
          type: type,
          title: title,
          amount: amount,
          detail: detail,
          createdAt: _nowLabel(),
        ),
      );
      if (history.length > 200) history = history.take(200).toList();
    });
    _saveHistory();
  }

  void _calculateSalary() {
    _dismissKeyboard();
    final salary = _parseMoney(salaryInput);
    if (salary == null || salary <= 0) {
      setState(() {
        salaryError = 'Informe um salário válido maior que zero.';
        salaryResult = null;
      });
      return;
    }

    final inss = _calculateInss(salary);
    final base = (salary - inss).clamp(0, double.infinity).toDouble();
    final irrf = _calculateIrrf(
      grossForReduction: salary,
      taxBase: base,
      dependents: 0,
      applySimplified: salarySimplified,
    );
    final net = salary - inss - irrf;

    setState(() {
      salaryError = null;
      salaryResult = {'gross': salary, 'inss': inss, 'irrf': irrf, 'net': net};
    });

    _logEvent('calculate_salary', {
      'gross_salary': salary,
      'net_salary': net,
      'simplified_irrf': salarySimplified,
    });
    _addHistory(
      'Salário',
      'Salário líquido',
      net,
      'Bruto ${brl.format(salary)} | INSS ${brl.format(inss)} | IRRF ${brl.format(irrf)}',
    );
  }

  void _calculateVacation() {
    _dismissKeyboard();
    final salary = _parseMoney(vacationSalaryInput);
    final overtime = _parseMoney(vacationOvertimeInput);
    final days = _parseIntOr(vacationDaysInput, 0);
    final deps = _parseIntOr(vacationDependentsInput, -1);

    if (salary == null ||
        salary <= 0 ||
        overtime == null ||
        overtime < 0 ||
        days < 1 ||
        days > 30 ||
        deps < 0) {
      setState(() {
        vacationError = 'Revise os campos de férias.';
        vacationResult = null;
      });
      return;
    }

    final reference = (salary + overtime).clamp(0, double.infinity);
    final vacationBase = reference * (days / 30.0);
    final oneThird = vacationBase / 3.0;
    final taxable = vacationBase + oneThird;
    final inss = _calculateInss(taxable);
    final irrf = _calculateIrrf(
      grossForReduction: taxable,
      taxBase: taxable - inss,
      dependents: deps,
      applySimplified: vacationSimplified,
    );
    final ad13 = vacationAdvance13 ? reference / 2.0 : 0.0;
    final net = taxable + ad13 - inss - irrf;

    setState(() {
      vacationError = null;
      vacationResult = {
        'days': days.toDouble(),
        'base': vacationBase,
        'third': oneThird,
        'ad13': ad13,
        'inss': inss,
        'irrf': irrf,
        'net': net,
      };
    });

    _logEvent('calculate_vacation', {
      'gross_salary': salary,
      'vacation_days': days,
      'advance_13': vacationAdvance13,
      'net_value': net,
    });
    _addHistory(
      'Férias',
      'Cálculo de férias',
      net,
      'Dias $days | 1/3 ${brl.format(oneThird)} | INSS ${brl.format(inss)}',
    );
  }

  void _calculateTermination() {
    _dismissKeyboard();
    final salary = _parseMoney(terminationSalaryInput);
    final days = _parseIntOr(terminationDaysInput, -1);
    final m13 = _parseIntOr(termination13Input, 0);
    final due = _parseIntOr(terminationVacationDueInput, -1);
    final prop = _parseIntOr(terminationVacationPropInput, 0);
    final fgts = _parseMoney(terminationFgtsInput) ?? 0;
    final deps = _parseIntOr(terminationDependentsInput, -1);

    if (salary == null || salary <= 0 || days < 0 || due < 0 || deps < 0) {
      setState(() {
        terminationError = 'Preencha os campos de rescisão corretamente.';
        terminationResult = null;
      });
      return;
    }

    final salaryBalance = (salary / 30.0) * days.clamp(0, 30);
    final vacationDue =
        (salary * due.clamp(0, 12)) + ((salary * due.clamp(0, 12)) / 3.0);
    final propBase = salary * (prop.clamp(0, 12) / 12.0);
    final fullVacationProp = propBase + (propBase / 3.0);

    final noticePay =
        terminationType == TerminationType.withoutCause &&
                employerNoticeIndemnified
            ? salary
            : 0.0;
    final noticeDiscount =
        terminationType == TerminationType.employeeResignation &&
                discountEmployeeNotice
            ? salary
            : 0.0;
    final thirteenth =
        terminationType == TerminationType.withCause
            ? 0.0
            : salary * (m13.clamp(0, 12) / 12.0);
    final vacationProp =
        terminationType == TerminationType.withCause ? 0.0 : fullVacationProp;
    final fgtsFine =
        terminationType == TerminationType.withoutCause ? (fgts * 0.40) : 0.0;

    final taxBaseGross = salaryBalance + thirteenth;
    final inss = _calculateInss(taxBaseGross);
    final irrf = _calculateIrrf(
      grossForReduction: taxBaseGross,
      taxBase: taxBaseGross - inss,
      dependents: deps.clamp(0, 20),
      applySimplified: terminationSimplified,
    );

    final net =
        salaryBalance +
        noticePay +
        thirteenth +
        vacationDue +
        vacationProp +
        fgtsFine -
        inss -
        irrf -
        noticeDiscount;

    setState(() {
      terminationError = null;
      terminationResult = {
        'salaryBalance': salaryBalance,
        'noticePay': noticePay,
        'noticeDiscount': noticeDiscount,
        'thirteenth': thirteenth,
        'vacationDue': vacationDue,
        'vacationProp': vacationProp,
        'fgtsFine': fgtsFine,
        'inss': inss,
        'irrf': irrf,
        'net': net,
      };
    });

    _logEvent('calculate_termination', {
      'termination_type': _terminationTypeKey(terminationType),
      'gross_salary': salary,
      'net_value': net,
    });
    _addHistory(
      'Rescisão',
      'Cálculo de rescisão',
      net,
      'Saldo ${brl.format(salaryBalance)} | 13º ${brl.format(thirteenth)} | FGTS ${brl.format(fgtsFine)}',
    );
  }

  Widget _buildBanner() {
    if (_bannerAd == null || !_isBannerReady) return const SizedBox.shrink();
    return AdWidget(ad: _bannerAd!);
  }

  int get _sectionIndex {
    switch (section) {
      case AppSection.calculators:
        return 0;
      case AppSection.history:
        return 1;
      case AppSection.settings:
        return 2;
    }
  }

  void _setSectionByIndex(int index) {
    switch (index) {
      case 0:
        _setSection(AppSection.calculators);
        break;
      case 1:
        _setSection(AppSection.history);
        break;
      case 2:
        _setSection(AppSection.settings);
        break;
    }
  }

  Widget _buildCurrentSection() {
    return switch (section) {
      AppSection.calculators => _buildCalculators(),
      AppSection.history => _buildHistory(),
      AppSection.settings => _buildSettings(),
    };
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Builder(
        builder:
            (drawerContext) => ListView(
              padding: EdgeInsets.zero,
              children: [
                const DrawerHeader(
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text('Menu', style: TextStyle(fontSize: 32)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: const Text('Calculadoras'),
                  selected: section == AppSection.calculators,
                  onTap: () {
                    _setSection(AppSection.calculators);
                    final scaffold = Scaffold.maybeOf(drawerContext);
                    if (scaffold != null) {
                      scaffold.closeDrawer();
                    } else if (Navigator.of(drawerContext).canPop()) {
                      Navigator.of(drawerContext).pop();
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Histórico'),
                  selected: section == AppSection.history,
                  onTap: () {
                    _setSection(AppSection.history);
                    final scaffold = Scaffold.maybeOf(drawerContext);
                    if (scaffold != null) {
                      scaffold.closeDrawer();
                    } else if (Navigator.of(drawerContext).canPop()) {
                      Navigator.of(drawerContext).pop();
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Configurações'),
                  selected: section == AppSection.settings,
                  onTap: () {
                    _setSection(AppSection.settings);
                    final scaffold = Scaffold.maybeOf(drawerContext);
                    if (scaffold != null) {
                      scaffold.closeDrawer();
                    } else if (Navigator.of(drawerContext).canPop()) {
                      Navigator.of(drawerContext).pop();
                    }
                  },
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildNavigationRail() {
    return NavigationRail(
      selectedIndex: _sectionIndex,
      onDestinationSelected: _setSectionByIndex,
      labelType: NavigationRailLabelType.all,
      minWidth: 92,
      leading: const Padding(
        padding: EdgeInsets.only(top: 12, bottom: 20),
        child: Icon(Icons.check_circle_outline, size: 32),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.calculate_outlined),
          selectedIcon: Icon(Icons.calculate),
          label: Text('Calculadoras'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history),
          label: Text('Histórico'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Configurações'),
        ),
      ],
    );
  }

  Widget _buildResponsiveBody({
    required bool wideLayout,
    required double maxContentWidth,
    required double horizontalPadding,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismissKeyboard,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: wideLayout ? 24 : 16,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: _buildCurrentSection(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CLT Brasil',
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
      ),
      home: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final wideLayout = width >= 1000;
          final tabletLayout = width >= 700 && width < 1000;
          final horizontalPadding =
              wideLayout
                  ? 40.0
                  : tabletLayout
                  ? 24.0
                  : 16.0;
          final maxContentWidth =
              wideLayout
                  ? 1040.0
                  : tabletLayout
                  ? 760.0
                  : double.infinity;
          final body = _buildResponsiveBody(
            wideLayout: wideLayout,
            maxContentWidth: maxContentWidth,
            horizontalPadding: horizontalPadding,
          );

          return Scaffold(
            appBar: AppBar(
              title: const Text('CLT Brasil'),
              centerTitle: wideLayout,
            ),
            drawer: wideLayout ? null : _buildDrawer(),
            bottomNavigationBar:
                (_bannerAd != null && _isBannerReady)
                    ? SafeArea(
                      top: false,
                      child: SizedBox(
                        height: _bannerAd!.size.height.toDouble(),
                        child: Center(
                          child: SizedBox(
                            width: _bannerAd!.size.width.toDouble(),
                            child: _buildBanner(),
                          ),
                        ),
                      ),
                    )
                    : null,
            body:
                wideLayout
                    ? Row(
                      children: [
                        _buildNavigationRail(),
                        const VerticalDivider(width: 1),
                        Expanded(child: body),
                      ],
                    )
                    : body,
          );
        },
      ),
    );
  }

  Widget _buildResultCard(List<Widget> children) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }

  void _showCalculationExplanation({
    required BuildContext context,
    required String title,
    required List<String> steps,
  }) {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children:
                    steps
                        .asMap()
                        .entries
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('${entry.key + 1}. ${entry.value}'),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  List<String> _salaryExplanationSteps() {
    final result = salaryResult;
    if (result == null) return const [];
    final gross = _mapDouble(result, 'gross');
    final inss = _mapDouble(result, 'inss');
    final irrf = _mapDouble(result, 'irrf');
    final net = _mapDouble(result, 'net');
    final irrfBase = (gross - inss).clamp(0, double.infinity).toDouble();
    const simplifiedDiscount = 607.20;
    final adjustedBase =
        (salarySimplified
                ? (irrfBase - simplifiedDiscount).clamp(0, double.infinity)
                : irrfBase)
            .toDouble();
    final irrfTable = _irrfRateAndDeduction(adjustedBase);
    final irrfRate = _mapDouble(irrfTable, 'rate');
    final irrfDeduction = _mapDouble(irrfTable, 'deduction');

    return [
      'Salário bruto informado: ${brl.format(gross)}.',
      'INSS segue tabela progressiva (7,5% a 14%). Enquadramento do salário: ${_inssBracketLabel(gross)}.',
      'Desconto total de INSS calculado por faixas: ${brl.format(inss)}.',
      'Base do IRRF: bruto - INSS = ${brl.format(irrfBase)}.',
      salarySimplified
          ? 'Desconto simplificado do IRRF aplicado (R\$ 607,20). Base ajustada: ${brl.format(adjustedBase)}.'
          : 'Desconto simplificado do IRRF desativado. Base ajustada: ${brl.format(adjustedBase)}.',
      'Faixa do IRRF: ${_irrfBracketLabel(adjustedBase)}. Alíquota ${_pct(irrfRate)} e parcela a deduzir ${brl.format(irrfDeduction)}.',
      'IRRF calculado: ${brl.format(irrf)}.',
      'Salário líquido final: bruto - INSS - IRRF = ${brl.format(net)}.',
    ];
  }

  List<String> _vacationExplanationSteps() {
    final result = vacationResult;
    if (result == null) return const [];
    final base = _mapDouble(result, 'base');
    final days = _mapDouble(result, 'days', 30);
    final third = _mapDouble(result, 'third');
    final inss = _mapDouble(result, 'inss');
    final irrf = _mapDouble(result, 'irrf');
    final ad13 = _mapDouble(result, 'ad13');
    final net = _mapDouble(result, 'net');
    final reference = days == 0 ? 0 : (base * 30) / days;
    final irrfBase = (base + third - inss).clamp(0, double.infinity).toDouble();
    const simplifiedDiscount = 607.20;
    final adjustedBase =
        (vacationSimplified
                ? (irrfBase - simplifiedDiscount).clamp(0, double.infinity)
                : irrfBase)
            .toDouble();
    final irrfTable = _irrfRateAndDeduction(adjustedBase);
    final irrfRate = _mapDouble(irrfTable, 'rate');
    final irrfDeduction = _mapDouble(irrfTable, 'deduction');

    return [
      'Remuneração de referência (salário + médias): ${brl.format(reference)}.',
      'Base de férias proporcional aos dias: ${brl.format(base)}.',
      'Adicional de 1/3 de férias: ${brl.format(third)}.',
      'INSS progressivo aplicado sobre férias + 1/3. Enquadramento: ${_inssBracketLabel(base + third)}.',
      'INSS total: ${brl.format(inss)}.',
      'Base do IRRF nas férias: (férias + 1/3) - INSS = ${brl.format(irrfBase)}.',
      'Faixa do IRRF: ${_irrfBracketLabel(adjustedBase)}. Alíquota ${_pct(irrfRate)} e dedução ${brl.format(irrfDeduction)}.',
      'IRRF total: ${brl.format(irrf)}.',
      vacationAdvance13
          ? 'Adiantamento da 1ª parcela do 13º incluído: ${brl.format(ad13)}.'
          : 'Sem adiantamento da 1ª parcela do 13º.',
      'Valor líquido de férias: ${brl.format(net)}.',
    ];
  }

  List<String> _terminationExplanationSteps() {
    final result = terminationResult;
    if (result == null) return const [];
    final salaryBalance = _mapDouble(result, 'salaryBalance');
    final thirteenth = _mapDouble(result, 'thirteenth');
    final taxBaseGross = salaryBalance + thirteenth;
    final inss = _mapDouble(result, 'inss');
    final irrfBase = (taxBaseGross - inss).clamp(0, double.infinity).toDouble();
    const simplifiedDiscount = 607.20;
    final adjustedBase =
        (terminationSimplified
                ? (irrfBase - simplifiedDiscount).clamp(0, double.infinity)
                : irrfBase)
            .toDouble();
    final irrfTable = _irrfRateAndDeduction(adjustedBase);
    final irrfRate = _mapDouble(irrfTable, 'rate');
    final irrfDeduction = _mapDouble(irrfTable, 'deduction');

    return [
      'Tipo de rescisão selecionado: ${_terminationTypeKey(terminationType)}.',
      'Saldo de salário: ${brl.format(result['salaryBalance'])}.',
      'Aviso prévio (crédito/desconto): +${brl.format(result['noticePay'])} e -${brl.format(result['noticeDiscount'])}.',
      '13º proporcional: ${brl.format(result['thirteenth'])}.',
      'Férias vencidas + 1/3: ${brl.format(result['vacationDue'])}.',
      'Férias proporcionais + 1/3: ${brl.format(result['vacationProp'])}.',
      'Multa de FGTS: ${brl.format(result['fgtsFine'])}.',
      'Base para INSS/IRRF na rescisão (saldo + 13º): ${brl.format(taxBaseGross)}.',
      'Enquadramento no INSS: ${_inssBracketLabel(taxBaseGross)}. INSS calculado: ${brl.format(inss)}.',
      'Base do IRRF após INSS: ${brl.format(irrfBase)}.',
      'Faixa do IRRF: ${_irrfBracketLabel(adjustedBase)}. Alíquota ${_pct(irrfRate)} e dedução ${brl.format(irrfDeduction)}.',
      'IRRF calculado: ${brl.format(result['irrf'])}.',
      'Líquido estimado final: ${brl.format(result['net'])}.',
    ];
  }

  Widget _buildCalculators() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Salário'),
                selected: calcTab == CalcTab.salary,
                onSelected: (_) => _setCalcTab(CalcTab.salary),
              ),
              ChoiceChip(
                label: const Text('Férias'),
                selected: calcTab == CalcTab.vacation,
                onSelected: (_) => _setCalcTab(CalcTab.vacation),
              ),
              ChoiceChip(
                label: const Text('Rescisão'),
                selected: calcTab == CalcTab.termination,
                onSelected: (_) => _setCalcTab(CalcTab.termination),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (calcTab == CalcTab.salary) _buildSalary(),
          if (calcTab == CalcTab.vacation) _buildVacation(),
          if (calcTab == CalcTab.termination) _buildTermination(),
        ],
      ),
    );
  }

  Widget _buildSalary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Salário bruto mensal',
            hintText: 'Ex.: 3.500,00',
          ),
          initialValue: salaryInput,
          onChanged: (v) {
            salaryInput = v;
            _saveString('salary_input', v);
          },
        ),
        SwitchListTile(
          title: const Text('Aplicar desconto simplificado do IRRF'),
          value: salarySimplified,
          onChanged: (v) {
            setState(() => salarySimplified = v);
            _saveBool('salary_simplified', v);
          },
        ),
        FilledButton(
          onPressed: _calculateSalary,
          child: const Text('Calcular salário líquido'),
        ),
        if (salaryError != null)
          Text(salaryError!, style: const TextStyle(color: Colors.red)),
        if (salaryResult != null)
          _buildResultCard([
            Text('Bruto: ${brl.format(salaryResult!['gross'])}'),
            Text('INSS: ${brl.format(salaryResult!['inss'])}'),
            Text('IRRF: ${brl.format(salaryResult!['irrf'])}'),
            Text(
              'Líquido: ${brl.format(salaryResult!['net'])}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ]),
        if (salaryResult != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder:
                  (buttonContext) => OutlinedButton.icon(
                    onPressed:
                        () => _showCalculationExplanation(
                          context: buttonContext,
                          title: 'Como calculamos o salario liquido',
                          steps: _salaryExplanationSteps(),
                        ),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Como calculamos'),
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildVacation() {
    Widget moneyField(
      String label,
      String value,
      String key,
      void Function(String) setter,
    ) {
      return TextFormField(
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        initialValue: value,
        onChanged: (v) {
          setter(v);
          _saveString(key, v);
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        moneyField(
          'Salário bruto mensal',
          vacationSalaryInput,
          'vac_salary_input',
          (v) => vacationSalaryInput = v,
        ),
        TextFormField(
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Quantidade de dias de férias (1 a 30)',
          ),
          initialValue: vacationDaysInput,
          onChanged: (v) {
            vacationDaysInput = v;
            _saveString('vac_days_input', v);
          },
        ),
        moneyField(
          'Média mensal de horas extras (R\$)',
          vacationOvertimeInput,
          'vac_overtime_input',
          (v) => vacationOvertimeInput = v,
        ),
        TextFormField(
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Dependentes'),
          initialValue: vacationDependentsInput,
          onChanged: (v) {
            vacationDependentsInput = v;
            _saveString('vac_dependents_input', v);
          },
        ),
        SwitchListTile(
          title: const Text('Adiantar 1ª parcela do 13º'),
          value: vacationAdvance13,
          onChanged: (v) {
            setState(() => vacationAdvance13 = v);
            _saveBool('vac_advance_13', v);
          },
        ),
        SwitchListTile(
          title: const Text('Aplicar desconto simplificado do IRRF'),
          value: vacationSimplified,
          onChanged: (v) {
            setState(() => vacationSimplified = v);
            _saveBool('vac_simplified', v);
          },
        ),
        FilledButton(
          onPressed: _calculateVacation,
          child: const Text('Calcular férias'),
        ),
        if (vacationError != null)
          Text(vacationError!, style: const TextStyle(color: Colors.red)),
        if (vacationResult != null)
          _buildResultCard([
            Text('Dias: ${_mapDouble(vacationResult!, 'days').toInt()}'),
            Text('Férias: ${brl.format(vacationResult!['base'])}'),
            Text('1/3: ${brl.format(vacationResult!['third'])}'),
            Text('Adiantamento 13º: ${brl.format(vacationResult!['ad13'])}'),
            Text('INSS: ${brl.format(vacationResult!['inss'])}'),
            Text('IRRF: ${brl.format(vacationResult!['irrf'])}'),
            Text(
              'Líquido: ${brl.format(vacationResult!['net'])}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ]),
        if (vacationResult != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder:
                  (buttonContext) => OutlinedButton.icon(
                    onPressed:
                        () => _showCalculationExplanation(
                          context: buttonContext,
                          title: 'Como calculamos as ferias',
                          steps: _vacationExplanationSteps(),
                        ),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Como calculamos'),
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildTermination() {
    String terminationLabel(TerminationType type) {
      switch (type) {
        case TerminationType.withoutCause:
          return 'Sem justa causa';
        case TerminationType.employeeResignation:
          return 'Pedido de demissão';
        case TerminationType.withCause:
          return 'Justa causa';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<TerminationType>(
          value: terminationType,
          isExpanded: true,
          items:
              TerminationType.values
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(terminationLabel(e)),
                    ),
                  )
                  .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => terminationType = v);
            _saveString('term_type', _terminationTypeKey(v));
          },
        ),
        _textField(
          'Salário bruto mensal',
          terminationSalaryInput,
          'term_salary_input',
          (v) => terminationSalaryInput = v,
          money: true,
        ),
        _textField(
          'Dias trabalhados no mês da saída',
          terminationDaysInput,
          'term_days_input',
          (v) => terminationDaysInput = v,
          integer: true,
        ),
        if (terminationType != TerminationType.withCause)
          _textField(
            'Meses para 13º proporcional',
            termination13Input,
            'term_m13_input',
            (v) => termination13Input = v,
            integer: true,
          ),
        _textField(
          'Quantidade de férias vencidas',
          terminationVacationDueInput,
          'term_due_input',
          (v) => terminationVacationDueInput = v,
          integer: true,
        ),
        if (terminationType != TerminationType.withCause)
          _textField(
            'Meses de férias proporcionais',
            terminationVacationPropInput,
            'term_prop_input',
            (v) => terminationVacationPropInput = v,
            integer: true,
          ),
        if (terminationType == TerminationType.withoutCause)
          _textField(
            'Saldo FGTS para multa 40% (R\$)',
            terminationFgtsInput,
            'term_fgts_input',
            (v) => terminationFgtsInput = v,
            money: true,
          ),
        _textField(
          'Dependentes',
          terminationDependentsInput,
          'term_dependents_input',
          (v) => terminationDependentsInput = v,
          integer: true,
        ),
        if (terminationType == TerminationType.withoutCause)
          SwitchListTile(
            title: const Text('Aviso prévio indenizado pelo empregador'),
            value: employerNoticeIndemnified,
            onChanged: (v) {
              setState(() => employerNoticeIndemnified = v);
              _saveBool('term_notice_indemnified', v);
            },
          ),
        if (terminationType == TerminationType.employeeResignation)
          SwitchListTile(
            title: const Text('Descontar aviso prévio não cumprido'),
            value: discountEmployeeNotice,
            onChanged: (v) {
              setState(() => discountEmployeeNotice = v);
              _saveBool('term_notice_discount', v);
            },
          ),
        SwitchListTile(
          title: const Text('Aplicar desconto simplificado do IRRF'),
          value: terminationSimplified,
          onChanged: (v) {
            setState(() => terminationSimplified = v);
            _saveBool('term_simplified', v);
          },
        ),
        FilledButton(
          onPressed: _calculateTermination,
          child: const Text('Calcular rescisão'),
        ),
        if (terminationError != null)
          Text(terminationError!, style: const TextStyle(color: Colors.red)),
        if (terminationResult != null)
          _buildResultCard([
            Text(
              'Saldo salário: ${brl.format(terminationResult!['salaryBalance'])}',
            ),
            Text(
              'Aviso prévio: ${brl.format(terminationResult!['noticePay'])}',
            ),
            Text(
              'Desconto aviso: ${brl.format(terminationResult!['noticeDiscount'])}',
            ),
            Text(
              '13º proporcional: ${brl.format(terminationResult!['thirteenth'])}',
            ),
            Text(
              'Férias vencidas + 1/3: ${brl.format(terminationResult!['vacationDue'])}',
            ),
            Text(
              'Férias proporcionais + 1/3: ${brl.format(terminationResult!['vacationProp'])}',
            ),
            Text('Multa FGTS: ${brl.format(terminationResult!['fgtsFine'])}'),
            Text('INSS: ${brl.format(terminationResult!['inss'])}'),
            Text('IRRF: ${brl.format(terminationResult!['irrf'])}'),
            Text(
              'Líquido estimado: ${brl.format(terminationResult!['net'])}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ]),
        if (terminationResult != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder:
                  (buttonContext) => OutlinedButton.icon(
                    onPressed:
                        () => _showCalculationExplanation(
                          context: buttonContext,
                          title: 'Como calculamos a rescisao',
                          steps: _terminationExplanationSteps(),
                        ),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Como calculamos'),
                  ),
            ),
          ),
      ],
    );
  }

  Widget _textField(
    String label,
    String value,
    String key,
    void Function(String) setter, {
    bool money = false,
    bool integer = false,
  }) {
    final keyboardType =
        money
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number;
    final formatters =
        integer
            ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
            : const <TextInputFormatter>[];

    return TextFormField(
      keyboardType: keyboardType,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label),
      initialValue: value,
      onChanged: (v) {
        setter(v);
        _saveString(key, v);
      },
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FilledButton(
              onPressed:
                  history.isEmpty
                      ? null
                      : () {
                        setState(() => history = []);
                        _saveHistory();
                      },
              child: const Text('Limpar histórico'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child:
              history.isEmpty
                  ? const Align(
                    alignment: Alignment.topLeft,
                    child: Text('Nenhum cálculo salvo ainda.'),
                  )
                  : ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final h = history[index];
                      return Card(
                        child: ListTile(
                          title: Text(h.title),
                          subtitle: Text('${h.detail}\n${h.createdAt}'),
                          isThreeLine: true,
                          trailing: Text(brl.format(h.amount)),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Modo escuro'),
          value: darkMode,
          onChanged: (v) {
            setState(() => darkMode = v);
            _saveBool('dark_mode', v);
            _logEvent('toggle_dark_mode', {'enabled': v});
          },
        ),
      ],
    );
  }
}

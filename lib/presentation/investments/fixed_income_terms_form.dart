import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../domain/economic_series/economic_series_observation.dart';
import '../../domain/investments/brazil_financial_calendar.dart';
import '../../domain/investments/fixed_income_contract.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../l10n/app_localizations.dart';

/// Contract details for one fixed-income acquisition lot.
///
/// Percentages are entered as percentages: 118 means 118% of the index,
/// while 1.2 in the spread field means 1.2 percentage points per year.
class FixedIncomeTermsForm extends StatefulWidget {
  const FixedIncomeTermsForm({
    required this.currency,
    required this.acquiredOn,
    required this.defaultProductName,
    this.initial,
    super.key,
  });

  final CurrencyCode currency;
  final LocalDate acquiredOn;
  final String defaultProductName;
  final FixedIncomeTerms? initial;

  @override
  FixedIncomeTermsFormState createState() => FixedIncomeTermsFormState();
}

class FixedIncomeTermsFormState extends State<FixedIncomeTermsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _product;
  late final TextEditingController _issuer;
  late final TextEditingController _principal;
  late final TextEditingController _accrualStart;
  late final TextEditingController _maturity;
  late final TextEditingController _liquidity;
  late final TextEditingController _annualRate;
  late final TextEditingController _multiplier;
  late final TextEditingController _spread;
  late final TextEditingController _lag;
  late final TextEditingController _anniversary;
  late FixedIncomeRemunerationMode _mode;
  late EconomicSeriesCode? _index;
  late int _basis;
  bool _productEdited = false;
  bool _startEdited = false;
  String? _combinationError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _product = TextEditingController(
      text: initial?.productName ?? widget.defaultProductName,
    );
    _issuer = TextEditingController(text: initial?.issuerName ?? '');
    _principal = TextEditingController(
      text: initial?.principal.toString() ?? '',
    );
    _accrualStart = TextEditingController(
      text: (initial?.accrualStart ?? widget.acquiredOn).toString(),
    );
    _maturity = TextEditingController(
      text: initial?.maturityOn?.toString() ?? '',
    );
    _liquidity = TextEditingController(
      text: initial?.liquidityOn?.toString() ?? '',
    );
    _annualRate = TextEditingController(
      text: _percentText(initial?.annualRate),
    );
    _multiplier = TextEditingController(
      text: _percentText(initial?.indexMultiplier),
    );
    _spread = TextEditingController(text: _percentText(initial?.annualSpread));
    _lag = TextEditingController(text: '${initial?.publicationLagMonths ?? 0}');
    _anniversary = TextEditingController(
      text: '${initial?.anniversaryDay ?? widget.acquiredOn.day}',
    );
    _mode = initial?.mode ?? FixedIncomeRemunerationMode.fixedAnnual;
    _index = initial?.indexCode;
    _basis = initial?.dayCountBasis ?? 365;
  }

  @override
  void didUpdateWidget(covariant FixedIncomeTermsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_productEdited &&
        widget.defaultProductName != oldWidget.defaultProductName) {
      _product.text = widget.defaultProductName;
    }
    if (!_startEdited && widget.acquiredOn != oldWidget.acquiredOn) {
      _accrualStart.text = widget.acquiredOn.toString();
      if (widget.initial == null &&
          _anniversary.text == '${oldWidget.acquiredOn.day}') {
        _anniversary.text = '${widget.acquiredOn.day}';
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _product,
      _issuer,
      _principal,
      _accrualStart,
      _maturity,
      _liquidity,
      _annualRate,
      _multiplier,
      _spread,
      _lag,
      _anniversary,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Returns null after presenting localized field errors for invalid terms.
  FixedIncomeTerms? buildTerms() {
    setState(() => _combinationError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    final mode = _mode;
    try {
      return FixedIncomeTerms(
        principal: _parseNumber(_principal.text)!,
        currency: widget.currency,
        productName: _product.text.trim(),
        issuerName: _issuer.text.trim().isEmpty ? null : _issuer.text.trim(),
        accrualStart: LocalDate.parse(_accrualStart.text.trim()),
        maturityOn: _optionalDate(_maturity.text),
        liquidityOn: _optionalDate(_liquidity.text),
        mode: mode,
        updateRule: switch (mode) {
          FixedIncomeRemunerationMode.fixedAnnual =>
            FixedIncomeUpdateRule.annualCompound,
          FixedIncomeRemunerationMode.dailyIndexPercent ||
          FixedIncomeRemunerationMode.dailyIndexSpread =>
            FixedIncomeUpdateRule.dailyObservation,
          FixedIncomeRemunerationMode.monthlyIndex =>
            FixedIncomeUpdateRule.monthlyAnniversary,
          FixedIncomeRemunerationMode.trValidity =>
            FixedIncomeUpdateRule.validityInterval,
          FixedIncomeRemunerationMode.manualOnly =>
            FixedIncomeUpdateRule.manualValue,
        },
        indexCode: switch (mode) {
          FixedIncomeRemunerationMode.dailyIndexPercent ||
          FixedIncomeRemunerationMode.dailyIndexSpread ||
          FixedIncomeRemunerationMode.monthlyIndex => _index,
          FixedIncomeRemunerationMode.trValidity => EconomicSeriesCode.trPeriod,
          _ => null,
        },
        annualRate: mode == FixedIncomeRemunerationMode.fixedAnnual
            ? _parseNumber(_annualRate.text)!.shift(-2)
            : null,
        indexMultiplier: mode == FixedIncomeRemunerationMode.dailyIndexPercent
            ? _parseNumber(_multiplier.text)!.shift(-2)
            : null,
        annualSpread:
            mode == FixedIncomeRemunerationMode.dailyIndexSpread ||
                (mode == FixedIncomeRemunerationMode.monthlyIndex &&
                    _spread.text.trim().isNotEmpty)
            ? _parseNumber(_spread.text)!.shift(-2)
            : null,
        dayCountBasis: switch (mode) {
          FixedIncomeRemunerationMode.fixedAnnual => _basis,
          FixedIncomeRemunerationMode.dailyIndexSpread => 252,
          _ => null,
        },
        calendarVersion: switch (mode) {
          FixedIncomeRemunerationMode.dailyIndexPercent ||
          FixedIncomeRemunerationMode.dailyIndexSpread =>
            BrazilFinancialCalendar.currentVersion,
          FixedIncomeRemunerationMode.fixedAnnual when _basis == 252 =>
            BrazilFinancialCalendar.currentVersion,
          _ => null,
        },
        publicationLagMonths: mode == FixedIncomeRemunerationMode.monthlyIndex
            ? int.parse(_lag.text.trim())
            : 0,
        anniversaryDay: mode == FixedIncomeRemunerationMode.monthlyIndex
            ? int.parse(_anniversary.text.trim())
            : null,
      );
    } on ArgumentError {
      setState(
        () => _combinationError = AppLocalizations.of(
          context,
        ).fixedIncomeInvalidCombinationMessage,
      );
      return null;
    } on FormatException {
      setState(
        () => _combinationError = AppLocalizations.of(
          context,
        ).fixedIncomeInvalidCombinationMessage,
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final daily =
        _mode == FixedIncomeRemunerationMode.dailyIndexPercent ||
        _mode == FixedIncomeRemunerationMode.dailyIndexSpread;
    final monthly = _mode == FixedIncomeRemunerationMode.monthlyIndex;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: const Key('fixed-income-product'),
            controller: _product,
            decoration: InputDecoration(labelText: l.fixedIncomeProductLabel),
            onChanged: (_) => _productEdited = true,
            validator: (value) => value == null || value.trim().isEmpty
                ? l.requiredFieldMessage
                : null,
          ),
          TextFormField(
            key: const Key('fixed-income-issuer'),
            controller: _issuer,
            decoration: InputDecoration(labelText: l.fixedIncomeIssuerLabel),
          ),
          TextFormField(
            key: const Key('fixed-income-principal'),
            controller: _principal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l.fixedIncomePrincipalLabel,
              suffixText: widget.currency.value,
            ),
            validator: (value) {
              final number = _parseNumber(value ?? '');
              if (number == null || number <= Decimal.zero) {
                return l.fixedIncomePositiveAmountMessage;
              }
              return null;
            },
          ),
          _dateField(
            key: const Key('fixed-income-accrual-start'),
            controller: _accrualStart,
            label: l.fixedIncomeAccrualStartLabel,
            isRequired: true,
            onChanged: () => _startEdited = true,
          ),
          _dateField(
            key: const Key('fixed-income-maturity'),
            controller: _maturity,
            label: l.fixedIncomeMaturityLabel,
          ),
          _dateField(
            key: const Key('fixed-income-liquidity'),
            controller: _liquidity,
            label: l.fixedIncomeLiquidityLabel,
          ),
          DropdownButtonFormField<FixedIncomeRemunerationMode>(
            key: const Key('fixed-income-mode'),
            initialValue: _mode,
            decoration: InputDecoration(labelText: l.fixedIncomeFormulaLabel),
            isExpanded: true,
            items: [
              for (final mode in FixedIncomeRemunerationMode.values)
                DropdownMenuItem(value: mode, child: Text(_modeLabel(l, mode))),
            ],
            validator: (value) =>
                value != null &&
                    _usesBrazilianIndex(value) &&
                    widget.currency != CurrencyCode.brl
                ? l.fixedIncomeBrlIndexOnlyMessage
                : null,
            onChanged: (value) => setState(() {
              _mode = value!;
              _index = _mode == FixedIncomeRemunerationMode.monthlyIndex
                  ? EconomicSeriesCode.ipcaMonthly
                  : _mode == FixedIncomeRemunerationMode.dailyIndexPercent ||
                        _mode == FixedIncomeRemunerationMode.dailyIndexSpread
                  ? EconomicSeriesCode.cdiDaily
                  : null;
              _combinationError = null;
            }),
          ),
          if (daily || monthly)
            DropdownButtonFormField<EconomicSeriesCode>(
              key: ValueKey('fixed-income-index-${_mode.name}'),
              initialValue: _index,
              decoration: InputDecoration(labelText: l.fixedIncomeIndexLabel),
              isExpanded: true,
              items: [
                for (final code
                    in monthly
                        ? const [
                            EconomicSeriesCode.ipcaMonthly,
                            EconomicSeriesCode.inpcMonthly,
                            EconomicSeriesCode.igpmMonthly,
                          ]
                        : const [
                            EconomicSeriesCode.cdiDaily,
                            EconomicSeriesCode.selicDaily,
                          ])
                  DropdownMenuItem(value: code, child: Text(_indexLabel(code))),
              ],
              validator: (value) =>
                  value == null ? l.requiredFieldMessage : null,
              onChanged: (value) => setState(() => _index = value),
            ),
          if (_mode == FixedIncomeRemunerationMode.fixedAnnual) ...[
            _percentageField(
              key: const Key('fixed-income-rate'),
              controller: _annualRate,
              label: l.fixedIncomeAnnualRateLabel,
              isRequired: true,
            ),
            DropdownButtonFormField<int>(
              key: const Key('fixed-income-basis'),
              initialValue: _basis,
              decoration: InputDecoration(
                labelText: l.fixedIncomeDayBasisLabel,
              ),
              items: [
                for (final basis in [252, 360, 365])
                  DropdownMenuItem(value: basis, child: Text('$basis')),
              ],
              onChanged: (value) => setState(() => _basis = value!),
            ),
          ],
          if (_mode == FixedIncomeRemunerationMode.dailyIndexPercent)
            _percentageField(
              key: const Key('fixed-income-multiplier'),
              controller: _multiplier,
              label: l.fixedIncomeMultiplierLabel,
              isRequired: true,
              nonnegative: true,
            ),
          if (_mode == FixedIncomeRemunerationMode.dailyIndexSpread || monthly)
            _percentageField(
              key: const Key('fixed-income-spread'),
              controller: _spread,
              label: l.fixedIncomeSpreadLabel,
              isRequired: !monthly,
            ),
          if (monthly) ...[
            TextFormField(
              key: const Key('fixed-income-anniversary'),
              controller: _anniversary,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.fixedIncomeAnniversaryLabel,
              ),
              validator: (value) {
                final day = int.tryParse(value?.trim() ?? '');
                return day == null || day < 1 || day > 31
                    ? l.fixedIncomeAnniversaryError
                    : null;
              },
            ),
            TextFormField(
              key: const Key('fixed-income-lag'),
              controller: _lag,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.fixedIncomeLagLabel),
              validator: (value) {
                final lag = int.tryParse(value?.trim() ?? '');
                return lag == null || lag < 0 || lag > 120
                    ? l.fixedIncomeLagError
                    : null;
              },
            ),
          ],
          if (_mode == FixedIncomeRemunerationMode.trValidity)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.fixedIncomeTrValidityDescription),
            ),
          if (_mode == FixedIncomeRemunerationMode.manualOnly)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.fixedIncomeManualRequiredLabel),
            ),
          if (_combinationError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _combinationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateField({
    required Key key,
    required TextEditingController controller,
    required String label,
    bool isRequired = false,
    VoidCallback? onChanged,
  }) {
    final l = AppLocalizations.of(context);
    return TextFormField(
      key: key,
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'YYYY-MM-DD',
        suffixIcon: IconButton(
          tooltip: l.dateLabel,
          icon: const Icon(Icons.calendar_today),
          onPressed: () async {
            final current = _optionalDate(controller.text) ?? widget.acquiredOn;
            final selected = await showDatePicker(
              context: context,
              initialDate: current.toUtcDate(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (selected != null) {
              controller.text = LocalDate(
                selected.year,
                selected.month,
                selected.day,
              ).toString();
              onChanged?.call();
              _formKey.currentState?.validate();
            }
          },
        ),
      ),
      onChanged: (_) => onChanged?.call(),
      validator: (value) {
        if ((value ?? '').trim().isEmpty) {
          return isRequired ? l.requiredFieldMessage : null;
        }
        final date = _optionalDate(value!);
        if (date == null) return l.fixedIncomeInvalidDateMessage;
        if (controller != _accrualStart) {
          final start = _optionalDate(_accrualStart.text);
          if (start != null && date.compareTo(start) < 0) {
            return l.fixedIncomeDateBeforeStartMessage;
          }
        }
        return null;
      },
    );
  }

  Widget _percentageField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required bool isRequired,
    bool nonnegative = false,
  }) {
    final l = AppLocalizations.of(context);
    return TextFormField(
      key: key,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(labelText: label, suffixText: '%'),
      validator: (value) {
        if ((value ?? '').trim().isEmpty && !isRequired) return null;
        final number = _parseNumber(value ?? '');
        if (number == null ||
            (nonnegative
                ? number < Decimal.zero
                : number <= Decimal.fromInt(-100))) {
          return l.fixedIncomeInvalidPercentageMessage;
        }
        return null;
      },
    );
  }

  String _modeLabel(AppLocalizations l, FixedIncomeRemunerationMode mode) =>
      switch (mode) {
        FixedIncomeRemunerationMode.fixedAnnual => l.fixedIncomeFixedAnnualMode,
        FixedIncomeRemunerationMode.dailyIndexPercent =>
          l.fixedIncomeDailyPercentMode,
        FixedIncomeRemunerationMode.dailyIndexSpread =>
          l.fixedIncomeDailySpreadMode,
        FixedIncomeRemunerationMode.monthlyIndex => l.fixedIncomeMonthlyMode,
        FixedIncomeRemunerationMode.trValidity => l.fixedIncomeTrMode,
        FixedIncomeRemunerationMode.manualOnly => l.fixedIncomeManualMode,
      };

  static bool _usesBrazilianIndex(FixedIncomeRemunerationMode mode) =>
      mode != FixedIncomeRemunerationMode.fixedAnnual &&
      mode != FixedIncomeRemunerationMode.manualOnly;

  String _indexLabel(EconomicSeriesCode code) => switch (code) {
    EconomicSeriesCode.cdiDaily => 'CDI',
    EconomicSeriesCode.selicDaily => 'Selic',
    EconomicSeriesCode.ipcaMonthly => 'IPCA',
    EconomicSeriesCode.inpcMonthly => 'INPC',
    EconomicSeriesCode.igpmMonthly => 'IGP-M',
    EconomicSeriesCode.trPeriod => 'TR',
  };

  static Decimal? _parseNumber(String text) {
    final value = text.trim();
    if (!RegExp(r'^-?\d+(?:[.,]\d+)?$').hasMatch(value)) return null;
    try {
      return Decimal.parse(value.replaceAll(',', '.'));
    } on FormatException {
      return null;
    }
  }

  static LocalDate? _optionalDate(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return LocalDate.parse(text.trim());
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static String _percentText(Decimal? decimal) =>
      decimal == null ? '' : decimal.shift(2).toString();
}

import 'dart:convert';
import 'dart:io';

import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/ledger/ledger_engine.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('financial golden is byte-identical on the native platform', () {
    final output = _evaluateFinancialGolden();

    expect(output, _expectedFinancialGolden);
    expect(Platform.isWindows || Platform.isAndroid, isTrue);
  });
}

String _evaluateFinancialGolden() {
  final engine = LedgerEngine();
  final vault = EntityId.parse('018f47c2-9b72-7cc1-8b83-5d0fead0a001');
  final category = EntityId.parse('018f47c2-9b72-7cc1-8b83-5d0fead0a002');
  final bank = _pocket(
    '018f47c2-9b72-7cc1-8b83-5d0fead0a003',
    CurrencyCode.brl,
    AccountNature.asset,
  );
  final savings = _pocket(
    '018f47c2-9b72-7cc1-8b83-5d0fead0a004',
    CurrencyCode.brl,
    AccountNature.asset,
  );
  final usd = _pocket(
    '018f47c2-9b72-7cc1-8b83-5d0fead0a005',
    CurrencyCode.usd,
    AccountNature.asset,
  );
  final card = _pocket(
    '018f47c2-9b72-7cc1-8b83-5d0fead0a006',
    CurrencyCode.brl,
    AccountNature.liability,
  );
  final date = LocalDate(2026, 8, 22);
  const now = UtcInstant.fromEpochMicroseconds(1787356800123456);
  Money brl(int minor) => Money(currency: CurrencyCode.brl, minorUnits: minor);

  final income = engine.income(
    vaultId: vault,
    pocket: bank,
    amount: brl(500000),
    categoryId: category,
    date: date,
    now: now,
  );
  final expense = engine.expense(
    vaultId: vault,
    pocket: bank,
    amount: brl(7250),
    categoryId: category,
    date: date,
    now: now,
  );
  final transfer = engine.transfer(
    vaultId: vault,
    source: bank,
    destination: savings,
    amount: brl(50000),
    date: date,
    now: now,
  );
  final exchange = engine.currencyExchange(
    vaultId: vault,
    source: bank,
    sourceAmount: brl(500000),
    destination: usd,
    destinationAmount: Money(currency: CurrencyCode.usd, minorUnits: 91000),
    exchangeRate: '5.4945054900',
    rateSource: 'manual',
    date: date,
    now: now,
  );
  final purchase = engine.creditCardPurchase(
    vaultId: vault,
    cardPocket: card,
    amount: brl(12000),
    categoryId: category,
    date: date,
    now: now,
  );
  final payment = engine.creditCardPayment(
    vaultId: vault,
    bankPocket: bank,
    cardPocket: card,
    amount: brl(12000),
    date: date,
    now: now,
  );

  return jsonEncode({
    'income': {
      'movement': income.movements.single.amountMinor,
      'classification': income.splits.single.money.minorUnits,
    },
    'expense': {
      'movement': expense.movements.single.amountMinor,
      'classification': expense.splits.single.money.minorUnits,
    },
    'transfer': {
      'net': transfer.movements.fold<int>(
        0,
        (sum, movement) => sum + movement.amountMinor,
      ),
      'classifications': transfer.splits.length,
    },
    'exchange': {
      'movements': [
        for (final movement in exchange.movements)
          '${movement.pocket.currency.value}:${movement.amountMinor}',
      ],
      'rate': exchange.fxConversion?.exchangeRate,
    },
    'card': {
      'purchaseMovement': purchase.movements.single.amountMinor,
      'purchaseClassification': purchase.splits.single.money.minorUnits,
      'paymentMovements': [
        for (final movement in payment.movements) movement.amountMinor,
      ],
      'paymentNetWorth': payment.netWorthEffectMinor,
      'paymentClassifications': payment.splits.length,
    },
  });
}

LedgerPocket _pocket(String id, CurrencyCode currency, AccountNature nature) =>
    LedgerPocket(id: EntityId.parse(id), currency: currency, nature: nature);

const _expectedFinancialGolden =
    '{"income":{"movement":500000,"classification":500000},'
    '"expense":{"movement":-7250,"classification":7250},'
    '"transfer":{"net":0,"classifications":0},'
    '"exchange":{"movements":["BRL:-500000","USD:91000"],'
    '"rate":"5.49450549"},'
    '"card":{"purchaseMovement":12000,"purchaseClassification":12000,'
    '"paymentMovements":[-12000,-12000],"paymentNetWorth":0,'
    '"paymentClassifications":0}}';

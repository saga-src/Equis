import 'package:equis/application/services/financial_intelligence_service.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled intelligence bypasses every reporting dependency', () async {
    const service = FinancialIntelligenceService.disabled();

    final report = await service.load(
      vaultId: EntityId.generate(),
      currency: CurrencyCode.brl,
      asOf: LocalDate(2026, 8, 22),
    );

    expect(report.enabled, isFalse);
    expect(report.insights, isEmpty);
  });
}

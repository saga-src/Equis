import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/presentation/investments/investment_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mutation failures remain in state and are rethrown to the UI',
    () async {
      final controller = InvestmentController(
        service: null,
        market: null,
        vaultId: EntityId.generate(),
        reportingCurrency: CurrencyCode.brl,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.createInstrument(
          name: 'Acme',
          symbol: 'ACME3',
          exchange: 'B3',
          assetClass: InvestmentAssetClass.stock,
          currency: CurrencyCode.brl,
        ),
        throwsA(isA<StateError>()),
      );

      expect(controller.state.loading, isFalse);
      expect(controller.state.error, isA<StateError>());
    },
  );
}

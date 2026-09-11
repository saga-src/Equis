import 'dart:convert';

import 'package:equis/domain/investments/investment_models.dart';
import 'package:equis/domain/market/market_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/infrastructure/market/edge_market_data_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'proxy request contains identifiers only and preserves decimal price',
    () async {
      late http.Request sent;
      final provider = EdgeMarketDataProvider(
        endpoint: Uri.parse(
          'https://example.supabase.co/functions/v1/market-quotes',
        ),
        publishableKey: 'public-key',
        accessTokenProvider: () async => 'access-token',
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            '{"price":"123.45000001","currency":"BRL",'
            '"timestamp":1000000,"provider":"brapi"}',
            200,
          );
        }),
      );
      final instrumentId = EntityId.generate();

      final quote = await provider.quote(
        MarketQuoteRequest(
          instrumentId: instrumentId,
          symbol: 'PETR4',
          assetClass: InvestmentAssetClass.stock,
          currency: CurrencyCode.brl,
          exchange: 'B3',
          provider: MarketProvider.brapi,
        ),
      );

      expect(sent.headers['apikey'], 'public-key');
      expect(sent.headers['authorization'], 'Bearer access-token');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body.keys, {
        'provider',
        'instrument_id',
        'symbol',
        'provider_symbol',
        'asset_class',
        'currency',
        'exchange',
      });
      expect(body.toString(), isNot(contains('transaction')));
      expect(body.toString(), isNot(contains('quantity')));
      expect(body.toString(), isNot(contains('balance')));
      expect(quote!.price.toString(), '123.45000001');
      expect(quote.instrumentId, instrumentId);
    },
  );

  test('proxy errors are isolated as provider-unavailable failures', () async {
    final provider = EdgeMarketDataProvider(
      endpoint: Uri.parse('https://example.invalid/market-quotes'),
      client: MockClient((_) async => http.Response('{}', 429)),
    );
    await expectLater(
      provider.quote(
        MarketQuoteRequest(
          instrumentId: EntityId.generate(),
          symbol: 'BTC',
          assetClass: InvestmentAssetClass.crypto,
          currency: CurrencyCode.usd,
          provider: MarketProvider.coinGecko,
        ),
      ),
      throwsA(isA<MarketProviderUnavailable>()),
    );
  });
}

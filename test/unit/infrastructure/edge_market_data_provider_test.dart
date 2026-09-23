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
        'operation',
        'assetId',
        'purpose',
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
      expect(body['purpose'], 'manualRefresh');
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

  test('uses public bearer when no cloud session exists', () async {
    late http.Request sent;
    final provider = EdgeMarketDataProvider(
      endpoint: Uri.parse('https://example.supabase.co/market-quotes'),
      publishableKey: 'public-key',
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          '{"price":"10","currency":"USD","timestamp":1,"provider":"twelve_data"}',
          200,
        );
      }),
    );

    await provider.quote(
      MarketQuoteRequest(
        instrumentId: EntityId.generate(),
        symbol: 'AAPL',
        assetClass: InvestmentAssetClass.stock,
        currency: CurrencyCode.usd,
        provider: MarketProvider.twelveData,
      ),
    );

    expect(sent.headers['authorization'], 'Bearer public-key');
  });

  test('retries a rejected session token with public bearer', () async {
    final sent = <http.Request>[];
    final provider = EdgeMarketDataProvider(
      endpoint: Uri.parse('https://example.supabase.co/market-quotes'),
      publishableKey: 'public-key',
      accessTokenProvider: () async => 'expired-token',
      client: MockClient((request) async {
        sent.add(request);
        if (sent.length == 1) return http.Response('{}', 401);
        return http.Response(
          '{"price":"10","currency":"USD","timestamp":1,"provider":"twelve_data"}',
          200,
        );
      }),
    );

    await provider.quote(
      MarketQuoteRequest(
        instrumentId: EntityId.generate(),
        symbol: 'AAPL',
        assetClass: InvestmentAssetClass.stock,
        currency: CurrencyCode.usd,
        provider: MarketProvider.twelveData,
      ),
    );

    expect(sent, hasLength(2));
    expect(sent.first.headers['authorization'], 'Bearer expired-token');
    expect(sent.last.headers['authorization'], 'Bearer public-key');
  });

  test('normalizes market discovery candidates and quote previews', () async {
    var requests = 0;
    final provider = EdgeMarketDataProvider(
      endpoint: Uri.parse('https://example.supabase.co/market-quotes'),
      publishableKey: 'public-key',
      client: MockClient((request) async {
        requests++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['operation'] == 'search') {
          return http.Response(
            '{"results":[{"assetId":"42","symbol":"BTC","name":"Bitcoin",'
            '"assetClass":"crypto","currency":"USD","exchange":null,'
            '"provider":"coinGecko","providerSymbol":"bitcoin"}]}',
            200,
          );
        }
        return http.Response(
          '{"price":"86477.12","currency":"USD","timestamp":2,'
          '"provider":"coingecko"}',
          200,
        );
      }),
    );

    final results = await provider.search(
      query: 'bit',
      assetClass: InvestmentAssetClass.crypto,
      currency: CurrencyCode.usd,
    );
    final preview = await provider.quoteCandidate(results.single);

    expect(results.single.providerSymbol, 'bitcoin');
    expect(results.single.assetId, '42');
    expect(results.single.provider, MarketProvider.coinGecko);
    expect(preview?.price.toString(), '86477.12');
    expect(requests, 2);
  });

  test('heartbeat contains only provider asset identities', () async {
    late Map<String, dynamic> body;
    final provider = EdgeMarketDataProvider(
      endpoint: Uri.parse('https://example.supabase.co/market-quotes'),
      publishableKey: 'public-key',
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"accepted":1}', 200);
      }),
    );

    await provider.heartbeat([
      MarketQuoteRequest(
        instrumentId: EntityId.generate(),
        symbol: 'AAPL',
        providerSymbol: 'AAPL',
        assetClass: InvestmentAssetClass.stock,
        currency: CurrencyCode.usd,
        exchange: 'NASDAQ',
        provider: MarketProvider.twelveData,
        purpose: MarketQuotePurpose.portfolio,
      ),
    ]);

    expect(body['operation'], 'heartbeat');
    final asset = (body['assets'] as List).single as Map<String, dynamic>;
    expect(asset, {
      'provider': 'twelveData',
      'providerSymbol': 'AAPL',
      'currency': 'USD',
      'exchange': 'NASDAQ',
    });
    expect(body.toString(), isNot(contains('instrumentId')));
    expect(body.toString(), isNot(contains('vault')));
    expect(body.toString(), isNot(contains('quantity')));
    expect(body.toString(), isNot(contains('balance')));
  });
}

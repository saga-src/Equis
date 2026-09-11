import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;

import '../../application/ports/market_data_ports.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';

final class EdgeMarketDataProvider implements MarketDataProvider {
  EdgeMarketDataProvider({
    required this.endpoint,
    this.publishableKey = '',
    this.accessTokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final Uri endpoint;
  final String publishableKey;
  final http.Client _client;
  final Future<String?> Function()? accessTokenProvider;

  @override
  Future<MarketQuote?> quote(MarketQuoteRequest request) async {
    if (endpoint.toString().isEmpty) {
      throw const MarketProviderUnavailable('proxy_not_configured');
    }
    final token = await accessTokenProvider?.call();
    final response = await _client.post(
      endpoint,
      headers: {
        'content-type': 'application/json',
        if (publishableKey.isNotEmpty) 'apikey': publishableKey,
        if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'provider': request.provider.name,
        'instrument_id': request.instrumentId.value,
        'symbol': request.symbol,
        'provider_symbol': request.providerSymbol,
        'asset_class': request.assetClass.stored,
        'currency': request.currency.value,
        'exchange': request.exchange,
      }),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MarketProviderUnavailable('proxy_${response.statusCode}');
    }
    final value = jsonDecode(response.body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid normalized quote.');
    }
    return MarketQuote(
      instrumentId: request.instrumentId,
      price: Decimal.parse(value['price']! as String),
      currency: CurrencyCode(value['currency']! as String),
      timestamp: UtcInstant.fromEpochMicroseconds(value['timestamp']! as int),
      provider: value['provider']! as String,
    );
  }

  @override
  Future<List<MarketQuote>> history(
    MarketQuoteRequest request, {
    required LocalDate from,
    required LocalDate through,
  }) async => const [];
}

final class MarketProviderUnavailable implements Exception {
  const MarketProviderUnavailable(this.reason);
  final String reason;
}

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;

import '../../application/ports/market_data_ports.dart';
import '../../domain/investments/investment_models.dart';
import '../../domain/market/market_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';

export '../../application/ports/market_data_ports.dart'
    show MarketProviderUnavailable;

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
  Future<void> heartbeat(List<MarketQuoteRequest> assets) async {
    final linked = assets
        .where((asset) => asset.providerSymbol?.trim().isNotEmpty == true)
        .toList(growable: false);
    for (var offset = 0; offset < linked.length; offset += 200) {
      final batch = linked.skip(offset).take(200);
      final response = await _post({
        'operation': 'heartbeat',
        'assets': [
          for (final asset in batch)
            {
              'provider': asset.provider.name,
              'providerSymbol': asset.providerSymbol,
              'currency': asset.currency.value,
              'exchange': asset.exchange,
            },
        ],
      });
      _requireSuccess(response);
    }
  }

  @override
  Future<List<MarketInstrumentCandidate>> search({
    required String query,
    required InvestmentAssetClass assetClass,
    required CurrencyCode currency,
    int limit = 10,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final response = await _post({
      'operation': 'search',
      'query': normalized,
      'asset_class': assetClass.stored,
      'currency': currency.value,
      'limit': limit.clamp(1, 10),
    });
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
      throw const MarketProviderUnavailable('invalid_response');
    }
    return [
      for (final item in decoded['results']! as List)
        if (item is Map<String, dynamic>) _candidate(item),
    ];
  }

  @override
  Future<MarketQuotePreview?> quoteCandidate(
    MarketInstrumentCandidate candidate,
  ) async {
    final response = await _post({
      'operation': 'quote',
      'assetId': candidate.assetId,
      'purpose': MarketQuotePurpose.preview.name,
      'provider': candidate.provider.name,
      'instrument_id': 'preview',
      'symbol': candidate.symbol,
      'provider_symbol': candidate.providerSymbol,
      'asset_class': candidate.assetClass.stored,
      'currency': candidate.currency.value,
      'exchange': candidate.exchange,
    });
    if (response.statusCode == 404) return null;
    _requireSuccess(response);
    final value = _quoteJson(response);
    return MarketQuotePreview(
      price: Decimal.parse(value['price']! as String),
      currency: CurrencyCode(value['currency']! as String),
      timestamp: UtcInstant.fromEpochMicroseconds(value['timestamp']! as int),
      provider: value['provider']! as String,
      stale: value['stale'] == true,
      refreshFailed:
          value['refreshFailed'] == true || value['refresh_failed'] == true,
      refreshFailure: _failureValue(value['errorCode'] ?? value['error_code']),
    );
  }

  @override
  Future<MarketQuote?> quote(MarketQuoteRequest request) async {
    final response = await _post({
      'operation': 'quote',
      'assetId': request.assetId,
      'purpose': request.purpose.name,
      'provider': request.provider.name,
      'instrument_id': request.instrumentId.value,
      'symbol': request.symbol,
      'provider_symbol': request.providerSymbol,
      'asset_class': request.assetClass.stored,
      'currency': request.currency.value,
      'exchange': request.exchange,
    });
    if (response.statusCode == 404) return null;
    _requireSuccess(response);
    final value = _quoteJson(response);
    return MarketQuote(
      instrumentId: request.instrumentId,
      price: Decimal.parse(value['price']! as String),
      currency: CurrencyCode(value['currency']! as String),
      timestamp: UtcInstant.fromEpochMicroseconds(value['timestamp']! as int),
      provider: value['provider']! as String,
      stale: value['stale'] == true,
      refreshFailed:
          value['refreshFailed'] == true || value['refresh_failed'] == true,
      refreshFailure: _failureValue(value['errorCode'] ?? value['error_code']),
    );
  }

  @override
  Future<List<MarketQuote>> history(
    MarketQuoteRequest request, {
    required LocalDate from,
    required LocalDate through,
  }) async => const [];

  Future<http.Response> _post(Map<String, Object?> body) async {
    if (endpoint.toString().isEmpty) {
      throw const MarketProviderUnavailable('proxy_not_configured');
    }
    final sessionToken = (await accessTokenProvider?.call())?.trim();
    final primary = sessionToken?.isNotEmpty == true
        ? sessionToken!
        : publishableKey;
    try {
      var response = await _send(body, primary);
      if (response.statusCode == 401 &&
          publishableKey.isNotEmpty &&
          primary != publishableKey) {
        response = await _send(body, publishableKey);
      }
      return response;
    } on http.ClientException {
      throw const MarketProviderUnavailable('network');
    }
  }

  Future<http.Response> _send(Map<String, Object?> body, String token) =>
      _client.post(
        endpoint,
        headers: {
          'content-type': 'application/json',
          if (publishableKey.isNotEmpty) 'apikey': publishableKey,
          if (token.isNotEmpty) 'authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

  void _requireSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final reason = switch (response.statusCode) {
      401 || 403 => 'unauthorized',
      429 => 'rate_limited',
      _ => 'proxy_${response.statusCode}',
    };
    throw MarketProviderUnavailable(reason);
  }

  Map<String, dynamic> _quoteJson(http.Response response) {
    final value = jsonDecode(response.body);
    if (value is! Map<String, dynamic> ||
        value['price'] is! String ||
        value['currency'] is! String ||
        value['timestamp'] is! int ||
        value['provider'] is! String) {
      throw const MarketProviderUnavailable('invalid_response');
    }
    return value;
  }

  MarketInstrumentCandidate _candidate(Map<String, dynamic> value) {
    try {
      return MarketInstrumentCandidate(
        assetId: (value['assetId'] ?? value['asset_id']) as String?,
        symbol: value['symbol']! as String,
        name: value['name']! as String,
        assetClass: InvestmentAssetClass.fromStorage(
          (value['assetClass'] ?? value['asset_class'])! as String,
        ),
        currency: CurrencyCode(value['currency']! as String),
        exchange: value['exchange'] as String?,
        provider: MarketProvider.values.byName(value['provider']! as String),
        providerSymbol:
            (value['providerSymbol'] ?? value['provider_symbol'])! as String,
      );
    } on Object {
      throw const MarketProviderUnavailable('invalid_response');
    }
  }

  MarketRefreshFailureKind? _failureValue(Object? value) {
    final reason = value?.toString();
    return switch (reason) {
      'unauthorized' => MarketRefreshFailureKind.unauthorized,
      'rate_limited' => MarketRefreshFailureKind.rateLimited,
      'invalid_provider_response' ||
      'invalid_response' => MarketRefreshFailureKind.invalidResponse,
      'network' || 'database_network' => MarketRefreshFailureKind.network,
      null || '' => null,
      _ => MarketRefreshFailureKind.providerUnavailable,
    };
  }
}

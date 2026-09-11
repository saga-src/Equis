import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/ports/fx_rate_ports.dart';
import '../../domain/fx/fx_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';

final class FrankfurterFxProvider implements FxRateProvider {
  FrankfurterFxProvider({http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse('https://api.frankfurter.dev');

  final http.Client _client;
  final Uri _endpoint;

  @override
  Future<FxRateQuote?> quote({
    required CurrencyCode base,
    required CurrencyCode quote,
    required LocalDate date,
  }) async {
    final uri = _endpoint.replace(
      path: '${_endpoint.path}/v2/rate/${base.value}/${quote.value}',
      queryParameters: {'date': date.toString()},
    );
    final response = await _client.get(uri);
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FxProviderException(
        provider: 'frankfurter_v2',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Frankfurter response.');
    }
    final returnedDate = LocalDate.parse(decoded['date']! as String);
    final rateMatch = RegExp(
      r'"rate"\s*:\s*([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)',
    ).firstMatch(response.body);
    if (rateMatch == null) {
      throw const FormatException('Frankfurter response has no decimal rate.');
    }
    return FxRateQuote(
      base: CurrencyCode(decoded['base']! as String),
      quote: CurrencyCode(decoded['quote']! as String),
      requestedDate: date,
      rateDate: returnedDate,
      rate: rateMatch.group(1)!,
      source: returnedDate == date
          ? FxRateSource.automaticExact
          : FxRateSource.previousMarketDay,
      provider: 'frankfurter_v2',
    );
  }
}

final class FxProviderException implements Exception {
  const FxProviderException({required this.provider, required this.statusCode});
  final String provider;
  final int statusCode;
}

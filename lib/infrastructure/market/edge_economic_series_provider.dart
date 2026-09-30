import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/ports/economic_series_ports.dart';
import '../../domain/economic_series/economic_series_observation.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/utc_instant.dart';

final class EdgeEconomicSeriesProvider implements EconomicSeriesProvider {
  EdgeEconomicSeriesProvider({
    required this.endpoint,
    this.publishableKey = '',
    this.accessTokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri endpoint;
  final String publishableKey;
  final Future<String?> Function()? accessTokenProvider;
  final http.Client _client;

  @override
  Future<List<EconomicSeriesObservation>> read({
    required EconomicSeriesCode code,
    required LocalDate from,
    required LocalDate through,
  }) async {
    if (endpoint.toString().isEmpty) {
      throw const EconomicSeriesProviderUnavailable('proxy_not_configured');
    }
    if (from.compareTo(through) > 0 ||
        through.toUtcDate().difference(from.toUtcDate()).inDays > 365) {
      throw ArgumentError('Series request exceeds the 366-day limit.');
    }
    final token = (await accessTokenProvider?.call())?.trim();
    final authorization = token?.isNotEmpty == true ? token! : publishableKey;
    http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              if (publishableKey.isNotEmpty) 'apikey': publishableKey,
              if (authorization.isNotEmpty)
                'authorization': 'Bearer $authorization',
            },
            body: jsonEncode({
              'operation': 'read',
              'code': code.sgsCode,
              'from': from.toString(),
              'through': through.toString(),
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const EconomicSeriesProviderUnavailable('timeout');
    } on http.ClientException {
      throw const EconomicSeriesProviderUnavailable('network');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EconomicSeriesProviderUnavailable(_failureCode(response));
    }
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> ||
          body['code'] != code.sgsCode ||
          body['unit'] != code.unit ||
          body['source'] != 'BCB_SGS' ||
          body['observations'] is! List) {
        throw const FormatException('Invalid series response.');
      }
      final values = <EconomicSeriesObservation>[];
      for (final item in body['observations'] as List) {
        if (item is! Map<String, dynamic> ||
            item['code'] != code.sgsCode ||
            item['unit'] != code.unit ||
            item['source'] != 'BCB_SGS' ||
            item['value'] is! String ||
            item['reference_start'] is! String ||
            item['reference_end'] is! String ||
            item['fetched_at'] is! String) {
          throw const FormatException('Invalid series observation.');
        }
        final start = LocalDate.parse(item['reference_start'] as String);
        final end = LocalDate.parse(item['reference_end'] as String);
        if (start.compareTo(through) > 0 || end.compareTo(from) < 0) {
          throw const FormatException('Observation outside requested range.');
        }
        final fetched = item['fetched_at'] as String;
        final parsedFetched = DateTime.parse(fetched);
        if (!parsedFetched.isUtc) {
          throw const FormatException('Observation timestamp must be UTC.');
        }
        values.add(
          EconomicSeriesObservation(
            code: code,
            referenceStart: start,
            referenceEnd: end,
            value: item['value'] as String,
            fetchedAt: UtcInstant.fromDateTime(parsedFetched),
          ),
        );
      }
      return values;
    } on Object {
      throw const EconomicSeriesProviderUnavailable('invalid_response');
    }
  }

  String _failureCode(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final code = body is Map<String, dynamic> ? body['error'] : null;
      if (code == 'feature_disabled' ||
          code == 'license_pending' ||
          code == 'database_unavailable') {
        return code as String;
      }
    } on FormatException {
      // Preserve the HTTP code when the body is not a structured error.
    }
    return 'http_${response.statusCode}';
  }
}

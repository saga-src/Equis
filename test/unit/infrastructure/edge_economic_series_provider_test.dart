import 'dart:convert';

import 'package:equis/application/ports/economic_series_ports.dart';
import 'package:equis/domain/economic_series/economic_series_observation.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/infrastructure/market/edge_economic_series_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'read sends only public code and range; accepts crossing TR interval',
    () async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.headers['authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode({
            'code': 226,
            'unit': 'percent_per_validity_period',
            'source': 'BCB_SGS',
            'observations': [
              {
                'code': 226,
                'unit': 'percent_per_validity_period',
                'source': 'BCB_SGS',
                'reference_start': '2026-09-15',
                'reference_end': '2026-10-15',
                'value': '0.1432',
                'fetched_at': '2026-09-24T12:00:00+00:00',
              },
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final provider = EdgeEconomicSeriesProvider(
        endpoint: Uri.parse(
          'https://example.test/functions/v1/economic-series',
        ),
        publishableKey: 'test-key',
        accessTokenProvider: () async => 'test-token',
        client: client,
      );
      final observations = await provider.read(
        code: EconomicSeriesCode.trPeriod,
        from: LocalDate(2026, 10, 1),
        through: LocalDate(2026, 10, 2),
      );
      expect(sent, {
        'operation': 'read',
        'code': 226,
        'from': '2026-10-01',
        'through': '2026-10-02',
      });
      expect(observations.single.referenceStart, LocalDate(2026, 9, 15));
      expect(observations.single.referenceEnd, LocalDate(2026, 10, 15));
    },
  );

  test('unit mismatch rejects the entire response', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'code': 12,
          'unit': 'percent_per_month',
          'source': 'BCB_SGS',
          'observations': [],
        }),
        200,
      ),
    );
    addTearDown(client.close);
    final provider = EdgeEconomicSeriesProvider(
      endpoint: Uri.parse('https://example.test/functions/v1/economic-series'),
      client: client,
    );
    await expectLater(
      provider.read(
        code: EconomicSeriesCode.cdiDaily,
        from: LocalDate(2026, 9, 1),
        through: LocalDate(2026, 9, 2),
      ),
      throwsA(isA<EconomicSeriesProviderUnavailable>()),
    );
  });

  test(
    'unpublished date differs from disabled, license and database errors',
    () async {
      String? failure;
      final client = MockClient(
        (_) async => failure != null
            ? http.Response(jsonEncode({'error': failure}), 503)
            : http.Response(
                jsonEncode({
                  'code': 12,
                  'unit': 'percent_per_day',
                  'source': 'BCB_SGS',
                  'observations': [],
                }),
                200,
              ),
      );
      addTearDown(client.close);
      final provider = EdgeEconomicSeriesProvider(
        endpoint: Uri.parse(
          'https://example.test/functions/v1/economic-series',
        ),
        client: client,
      );
      final date = LocalDate(2024, 9, 7); // Weekend: no CDI publication.
      expect(
        await provider.read(
          code: EconomicSeriesCode.cdiDaily,
          from: date,
          through: date,
        ),
        isEmpty,
      );
      for (final reason in [
        'feature_disabled',
        'license_pending',
        'database_unavailable',
      ]) {
        failure = reason;
        await expectLater(
          provider.read(
            code: EconomicSeriesCode.cdiDaily,
            from: date,
            through: date,
          ),
          throwsA(
            isA<EconomicSeriesProviderUnavailable>().having(
              (error) => error.reason,
              'reason',
              reason,
            ),
          ),
        );
      }
    },
  );
}

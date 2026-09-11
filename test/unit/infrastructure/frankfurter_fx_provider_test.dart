import 'package:equis/domain/fx/fx_models.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/infrastructure/fx/frankfurter_fx_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Frankfurter v2 preserves the response decimal lexeme', () async {
    late Uri requested;
    final provider = FrankfurterFxProvider(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '{"date":"2026-08-13","base":"USD","quote":"BRL","rate":5.4372819300}',
          200,
        );
      }),
    );
    final quote = await provider.quote(
      base: CurrencyCode.usd,
      quote: CurrencyCode.brl,
      date: LocalDate.parse('2026-08-13'),
    );
    expect(requested.path, '/v2/rate/USD/BRL');
    expect(requested.queryParameters['date'], '2026-08-13');
    expect(quote?.rate, '5.43728193');
    expect(quote?.source, FxRateSource.automaticExact);
  });

  test(
    'Frankfurter response from a prior market day is marked estimated',
    () async {
      final provider = FrankfurterFxProvider(
        client: MockClient(
          (_) async => http.Response(
            '{"date":"2026-08-12","base":"USD","quote":"BRL","rate":5.41}',
            200,
          ),
        ),
      );
      final quote = await provider.quote(
        base: CurrencyCode.usd,
        quote: CurrencyCode.brl,
        date: LocalDate.parse('2026-08-13'),
      );
      expect(quote?.source, FxRateSource.previousMarketDay);
      expect(quote?.isEstimated, isTrue);
    },
  );
}

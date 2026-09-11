import 'package:equis/core/errors/app_failure.dart';
import 'package:equis/core/errors/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('success exposes its value without throwing', () {
    const result = Success<int>(42);

    expect(
      result.fold(onSuccess: (value) => value, onFailure: (failure) => -1),
      42,
    );
  });

  test('failure exposes a typed safe error code', () {
    const result = Failure<int>(ValidationFailure(code: 'invalid_value'));

    expect(
      result.fold(
        onSuccess: (value) => 'success',
        onFailure: (failure) => failure.code,
      ),
      'invalid_value',
    );
  });
}

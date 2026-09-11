import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Supabase Auth remains behind the infrastructure gateway', () {
    final presentation = Directory('lib/presentation/cloud')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');
    final application = [
      File('lib/application/ports/cloud_identity_ports.dart'),
      File('lib/application/services/cloud_account_service.dart'),
    ].map((file) => file.readAsStringSync()).join('\n');
    final gateway = File(
      'lib/infrastructure/cloud/supabase_cloud_auth_gateway.dart',
    ).readAsStringSync();

    expect(presentation, isNot(contains('supabase_flutter')));
    expect(application, isNot(contains('supabase_flutter')));
    expect(gateway, contains('supabase_flutter'));
    expect(gateway, isNot(contains('transaction')));
    expect(gateway, isNot(contains('account_movements')));
    expect(gateway, isNot(contains('sync_records')));
  });
}

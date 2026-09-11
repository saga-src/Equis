import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attachment storage migration is private and vault scoped', () async {
    final sql = await File(
      'supabase/migrations/202608220002_phase19_attachment_storage.sql',
    ).readAsString();

    expect(sql, contains("'equis-attachments'"));
    expect(sql, contains('public = false'));
    expect(sql, contains("array['application/octet-stream']"));
    expect(sql, contains('to authenticated'));
    expect(sql, contains('public.is_vault_attachment_path_member(name)'));
    expect(sql, contains("split_part(p_name, '/', 1) = 'vault'"));
    expect(sql, contains("split_part(p_name, '/', 3) = 'attachments'"));
    expect(sql, contains('vm.user_id = (select auth.uid())'));
    expect(sql, isNot(contains('to anon')));
    expect(sql, isNot(contains('public = true')));
  });
}

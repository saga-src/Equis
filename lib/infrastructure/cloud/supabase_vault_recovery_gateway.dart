import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/ports/vault_recovery_ports.dart';
import '../../application/ports/cloud_sync_gateway.dart';

final class SupabaseVaultRecoveryGateway
    implements VaultRecoveryRecordGateway, CloudVaultRecoveryDiscoveryGateway {
  const SupabaseVaultRecoveryGateway(this.client);
  final SupabaseClient client;

  @override
  Future<void> publishWrappedRecord({
    required String vaultId,
    required int keyVersion,
    required Map<String, Object> wrappedRecord,
  }) async {
    if (wrappedRecord['vault_id'] != vaultId ||
        wrappedRecord['key_version'] != keyVersion ||
        wrappedRecord.keys.toSet().difference(_columns).isNotEmpty) {
      throw const CloudSyncFormatException();
    }
    final payload = <String, Object?>{
      for (final entry in wrappedRecord.entries)
        entry.key: entry.value is List<int>
            ? '\\x${_hex(entry.value as List<int>)}'
            : entry.value,
    };
    try {
      // Enrollment must never replace another installation's recovery key.
      // A duplicate vault is an error, including concurrent enrollment races.
      await client.from('vault_key_recovery').insert(payload);
    } on PostgrestException catch (error) {
      throw CloudSyncFailure(
        error.code == '42501'
            ? CloudSyncFailureCode.accessDenied
            : CloudSyncFailureCode.remote,
      );
    } on Exception {
      throw const CloudSyncFailure(CloudSyncFailureCode.network);
    }
  }

  @override
  Future<Map<String, Object>?> fetchWrappedRecord({
    required String vaultId,
    required int keyVersion,
  }) async {
    try {
      final row = await client
          .from('vault_key_recovery')
          .select(_columns.join(','))
          .eq('vault_id', vaultId)
          .eq('key_version', keyVersion)
          .maybeSingle();
      if (row == null) return null;
      return {
        for (final key in _columns)
          key: switch (key) {
            'wrapped_vault_key' || 'salt' || 'nonce' => _bytea(row[key]),
            _ => row[key] as Object,
          },
      };
    } on PostgrestException catch (error) {
      throw CloudSyncFailure(
        error.code == '42501'
            ? CloudSyncFailureCode.accessDenied
            : CloudSyncFailureCode.remote,
      );
    } on CloudSyncFormatException {
      rethrow;
    } on Exception {
      throw const CloudSyncFailure(CloudSyncFailureCode.network);
    }
  }

  @override
  Future<List<Map<String, Object>>> listAccessibleWrappedRecords() async {
    try {
      final rows = await client
          .from('vault_key_recovery')
          .select(_columns.join(','));
      return [
        for (final row in rows)
          {
            for (final key in _columns)
              key: switch (key) {
                'wrapped_vault_key' || 'salt' || 'nonce' => _bytea(row[key]),
                _ => row[key] as Object,
              },
          },
      ];
    } on PostgrestException catch (error) {
      throw CloudSyncFailure(
        error.code == '42501'
            ? CloudSyncFailureCode.accessDenied
            : CloudSyncFailureCode.remote,
      );
    } on CloudSyncFormatException {
      rethrow;
    } on Exception {
      throw const CloudSyncFailure(CloudSyncFailureCode.network);
    }
  }
}

const _columns = {
  'vault_id',
  'wrapped_vault_key',
  'kdf',
  'kdf_parameters',
  'salt',
  'nonce',
  'key_version',
};

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytea(Object? value) {
  if (value is Uint8List) return value;
  if (value is! String || !value.startsWith(r'\x')) {
    throw const CloudSyncFormatException();
  }
  final hex = value.substring(2);
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    throw const CloudSyncFormatException();
  }
  return Uint8List.fromList([
    for (var index = 0; index < hex.length; index += 2)
      int.parse(hex.substring(index, index + 2), radix: 16),
  ]);
}

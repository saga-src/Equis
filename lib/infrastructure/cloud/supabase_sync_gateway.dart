import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/ports/cloud_sync_gateway.dart';
import '../security/vault_key_manager.dart';
import '../security/vault_identity.dart';
import '../../application/sync/encrypted_sync_models.dart';

final class SupabaseSyncGateway
    implements CloudSyncGateway, CloudSyncWakeupGateway {
  const SupabaseSyncGateway(this.client, {this.keys});
  final VaultKeyManager? keys;
  bool get usesVaultIdentity => keys?.protocolVersion == 2;
  String get _records => 'sync_records';
  final SupabaseClient client;

  @override
  Future<void> ensureVaultAndDevice({
    required String vaultId,
    required String deviceId,
    List<int>? devicePublicKey,
  }) async {
    if (usesVaultIdentity) {
      final identity = await keys!.requireVault(vaultId);
      final user = client.auth.currentUser?.id;
      if (user == null) {
        throw const CloudSyncFailure(CloudSyncFailureCode.sessionExpired);
      }
      if (identity.ownerId != null && identity.ownerId != user) {
        throw const CloudSyncFailure(CloudSyncFailureCode.accessDenied);
      }
      final fingerprint = await identity.fingerprint();
      await _translate(
        () => client.rpc<void>(
          'register_vault',
          params: {
            'p_vault_id': vaultId,
            'p_device_id': deviceId,
            'p_key_fingerprint': fingerprint,
          },
        ),
      );
      await keys!.installVaultIdentity(
        VaultIdentity(
          vaultId: vaultId,
          masterKey: identity.masterKey,
          ownerId: user,
        ),
      );
      return;
    }
    await _translate(
      () => client.rpc<void>(
        'create_equis_vault',
        params: {
          'p_vault_id': vaultId,
          'p_device_id': deviceId,
          'p_device_public_key_hex': devicePublicKey == null
              ? null
              : _hex(devicePublicKey),
        },
      ),
    );
  }

  @override
  Future<List<CloudPushResult>> pushBatch({
    required String vaultId,
    required List<CloudSyncMutation> mutations,
  }) async {
    if (mutations.isEmpty || mutations.length > 100) {
      throw ArgumentError.value(mutations.length, 'mutations');
    }
    final fingerprint = usesVaultIdentity
        ? await (await keys!.requireVault(vaultId)).fingerprint()
        : null;
    final response = await _translate(
      () => client.rpc<List<dynamic>>(
        'apply_sync_batch',
        params: {
          'p_vault_id': vaultId,
          'p_mutations': mutations.map(_mutationJson).toList(growable: false),
          if (usesVaultIdentity) 'p_key_fingerprint': fingerprint,
        },
      ),
    );
    return response
        .map((value) {
          if (value is! Map<String, dynamic>) {
            throw const CloudSyncFormatException();
          }
          final status = switch (value['status']) {
            'accepted' => CloudPushStatus.accepted,
            'conflict' => CloudPushStatus.conflict,
            _ => throw const CloudSyncFormatException(),
          };
          return CloudPushResult(
            operationId: _string(value, 'operation_id'),
            status: status,
            revision: _nullableInt(value['revision']),
            remoteRevision: _nullableInt(value['remote_revision']),
            serverVersion: _nullableInt(value['server_version']),
            idempotentReplay: value['idempotent_replay'] == true,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<CloudSyncRecord>> pull({
    required String vaultId,
    required int afterServerVersion,
    int limit = 100,
  }) async {
    if (afterServerVersion < 0 || limit < 1 || limit > 500) {
      throw ArgumentError('Invalid pull cursor or limit.');
    }
    final response = await _translate(
      () => client
          .from(_records)
          .select()
          .eq('vault_id', vaultId)
          .gt('server_version', afterServerVersion)
          .order('server_version', ascending: true)
          .limit(limit),
    );
    return response.map(_cloudRecord).toList(growable: false);
  }

  @override
  Future<CloudSyncRecord?> fetch({
    required String vaultId,
    required String entityType,
    required String recordId,
  }) async {
    final response = await _translate(
      () => client
          .from(_records)
          .select()
          .eq('vault_id', vaultId)
          .eq('entity_type', entityType)
          .eq('record_id', recordId)
          .maybeSingle(),
    );
    return response == null ? null : _cloudRecord(response);
  }

  @override
  Future<void> acknowledgeCursor({
    required String vaultId,
    required String deviceId,
    required int serverVersion,
  }) => _translate(
    () => client.rpc<void>(
      'acknowledge_sync_cursor',
      params: {
        'p_vault_id': vaultId,
        'p_device_id': deviceId,
        'p_server_version': serverVersion,
      },
    ),
  );

  @override
  Stream<void> wakeups({required String vaultId}) => client
      .from(_records)
      .stream(primaryKey: ['vault_id', 'entity_type', 'record_id'])
      .eq('vault_id', vaultId)
      .map((_) {});

  Map<String, Object?> _mutationJson(CloudSyncMutation mutation) {
    final record = mutation.record;
    return {
      'operation_id': mutation.operationId,
      'entity_type': record.identity.entityType,
      'record_id': record.identity.recordId,
      'expected_revision': mutation.expectedRevision,
      'new_revision': record.identity.revision,
      'cipher_version': record.envelope.cipherVersion,
      'nonce_hex': _hex(record.envelope.nonce),
      'ciphertext_hex': _hex(record.envelope.cloudCiphertext),
      'is_deleted': record.isDeleted,
    };
  }

  CloudSyncRecord _cloudRecord(Map<String, dynamic> row) {
    final identity = SyncRecordIdentity(
      vaultId: _string(row, 'vault_id'),
      recordId: _string(row, 'record_id'),
      entityType: _string(row, 'entity_type'),
      revision: _int(row, 'revision'),
    );
    return CloudSyncRecord(
      record: EncryptedSyncRecord(
        identity: identity,
        envelope: EncryptedPayloadEnvelope.fromCloud(
          cipherVersion: _int(row, 'cipher_version'),
          nonce: _bytea(row['nonce']),
          ciphertext: _bytea(row['ciphertext']),
        ),
        isDeleted: row['is_deleted'] == true,
      ),
      serverVersion: _int(row, 'server_version'),
    );
  }
}

Future<T> _translate<T>(Future<T> Function() action) async {
  try {
    return await action().timeout(const Duration(seconds: 30));
  } on PostgrestException catch (error) {
    final code = switch (error.code) {
      'EVK01' => CloudSyncFailureCode.keyMismatch,
      'EVP01' => CloudSyncFailureCode.clientObsolete,
      '42501' => CloudSyncFailureCode.accessDenied,
      '22023' => CloudSyncFailureCode.invalidMutation,
      'PGRST301' ||
      'PGRST302' ||
      'PGRST303' => CloudSyncFailureCode.sessionExpired,
      'PGRST202' ||
      'PGRST204' ||
      'PGRST205' ||
      '42P01' ||
      '42703' ||
      '42883' => CloudSyncFailureCode.incompatibleServer,
      _ => CloudSyncFailureCode.remote,
    };
    throw CloudSyncFailure(code);
  } on AuthException {
    throw const CloudSyncFailure(CloudSyncFailureCode.sessionExpired);
  } on CloudSyncFormatException {
    rethrow;
  } on Exception {
    throw const CloudSyncFailure(CloudSyncFailureCode.network);
  }
}

String _hex(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

List<int> _bytea(Object? value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return value;
  if (value is! String) throw const CloudSyncFormatException();
  final hex = value.startsWith(r'\x') ? value.substring(2) : value;
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
    throw const CloudSyncFormatException();
  }
  return List<int>.generate(
    hex.length ~/ 2,
    (index) => int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
    growable: false,
  );
}

String _string(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String) throw const CloudSyncFormatException();
  return result;
}

int _int(Map<String, dynamic> value, String key) {
  final result = _nullableInt(value[key]);
  if (result == null) throw const CloudSyncFormatException();
  return result;
}

int? _nullableInt(Object? value) => switch (value) {
  null => null,
  int() => value,
  String() => int.tryParse(value),
  _ => null,
};

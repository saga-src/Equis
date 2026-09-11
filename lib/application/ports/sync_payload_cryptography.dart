import '../sync/encrypted_sync_models.dart';

abstract interface class SyncPayloadCryptography {
  Future<EncryptedPayloadEnvelope> encrypt({
    required SyncRecordIdentity identity,
    required Map<String, Object?> payload,
    int? keyVersion,
    List<int>? nonce,
  });

  Future<Map<String, Object?>> decrypt({
    required SyncRecordIdentity identity,
    required EncryptedPayloadEnvelope envelope,
  });
}

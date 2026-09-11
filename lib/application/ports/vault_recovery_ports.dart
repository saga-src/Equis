import 'dart:typed_data';

/// Cloud boundary for already-wrapped vault keys. Implementations must never
/// accept a plaintext vault master key or a recovery secret.
abstract interface class VaultRecoveryRecordGateway {
  Future<void> publishWrappedRecord({
    required String vaultId,
    required int keyVersion,
    required Map<String, Object> wrappedRecord,
  });

  Future<Map<String, Object>?> fetchWrappedRecord({
    required String vaultId,
    required int keyVersion,
  });
}

abstract interface class CloudVaultRecoveryDiscoveryGateway {
  Future<List<Map<String, Object>>> listAccessibleWrappedRecords();
}

/// Approval boundary for a future trusted-device flow. The payload crossing
/// this boundary is sealed specifically for the requesting device.
abstract interface class TrustedDeviceKeyTransferGateway {
  Future<String> requestApproval({
    required String vaultId,
    required String requestingDeviceId,
    required Uint8List requestingDevicePublicKey,
  });

  Future<void> approve({
    required String requestId,
    required Uint8List sealedTransferPackage,
  });

  Future<Uint8List?> receiveApprovedPackage({required String requestId});
}

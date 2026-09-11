abstract interface class SyncEnrollmentStore {
  Future<void> seedAndEnable({
    required String vaultId,
    required String authUserId,
  });
}

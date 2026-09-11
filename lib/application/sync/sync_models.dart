enum SyncEntityType {
  vault('vault'),
  account('account'),
  category('category'),
  counterparty('counterparty'),
  tag('tag'),
  transaction('transaction'),
  recurringRule('recurring_rule'),
  installmentPlan('installment_plan'),
  creditCardStatement('credit_card_statement'),
  budget('budget'),
  goal('goal'),
  asset('asset'),
  investmentInstrument('investment_instrument'),
  manualFxRate('manual_fx_rate'),
  manualMarketPrice('manual_market_price'),
  attachment('attachment');

  const SyncEntityType(this.wireName);
  final String wireName;

  static SyncEntityType parse(String value) => values.firstWhere(
    (type) => type.wireName == value,
    orElse: () => throw const FormatException('Unknown sync entity type.'),
  );
}

enum SyncOperation { upsert, delete }

enum LocalSyncState { localOnly, pending, synced, conflict, deletedPending }

final class PendingSyncMutation {
  const PendingSyncMutation({
    required this.operationId,
    required this.vaultId,
    required this.entityType,
    required this.recordId,
    required this.baseRevision,
    required this.baseSnapshot,
    required this.newRevision,
    required this.operation,
    required this.createdAtMicros,
    required this.attemptCount,
    this.nextRetryAtMicros,
    this.lastErrorCode,
  });

  final String operationId;
  final String vaultId;
  final SyncEntityType entityType;
  final String recordId;
  final int? baseRevision;
  final Map<String, Object?>? baseSnapshot;
  final int newRevision;
  final SyncOperation operation;
  final int createdAtMicros;
  final int attemptCount;
  final int? nextRetryAtMicros;
  final String? lastErrorCode;
}

final class SyncCursorValue {
  const SyncCursorValue({
    required this.vaultId,
    required this.lastServerVersion,
    this.lastPullAtMicros,
    this.lastPushAtMicros,
    this.lastSuccessAtMicros,
  });

  final String vaultId;
  final int lastServerVersion;
  final int? lastPullAtMicros;
  final int? lastPushAtMicros;
  final int? lastSuccessAtMicros;
}

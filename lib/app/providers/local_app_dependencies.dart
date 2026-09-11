import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/ports/cloud_identity_ports.dart';
import '../../application/services/cloud_account_service.dart';
import '../../application/services/existing_vault_restore_service.dart';
import '../../application/services/attachment_service.dart';
import '../../application/services/everyday_transaction_service.dart';
import '../../application/services/budget_service.dart';
import '../../application/services/goal_service.dart';
import '../../application/services/wealth_service.dart';
import '../../application/services/investment_service.dart';
import '../../application/services/market_data_service.dart';
import '../../application/services/fx_rate_selector.dart';
import '../../application/services/financial_intelligence_service.dart';
import '../../core/config/app_config.dart';
import '../../domain/cloud/cloud_identity_models.dart';
import '../../application/services/cash_flow_projection_service.dart';
import '../../application/services/credit_card_service.dart';
import '../../application/services/dashboard_service.dart';
import '../../application/services/local_finance_container_service.dart';
import '../../application/services/local_finance_session_service.dart';
import '../../application/services/taxonomy_service.dart';
import '../../infrastructure/persistence/database/drift_local_unit_of_work.dart';
import '../../infrastructure/persistence/database/local_database_lifecycle.dart';
import '../../infrastructure/persistence/database/secure_storage_local_database_key_provider.dart';
import '../../infrastructure/repositories/drift_foundational_repositories.dart';
import '../../infrastructure/repositories/drift_budget_repository.dart';
import '../../infrastructure/repositories/drift_goal_repository.dart';
import '../../infrastructure/repositories/drift_wealth_repository.dart';
import '../../infrastructure/repositories/drift_investment_repository.dart';
import '../../infrastructure/repositories/drift_market_price_repository.dart';
import '../../infrastructure/repositories/drift_fx_repositories.dart';
import '../../infrastructure/market/edge_market_data_provider.dart';
import '../../infrastructure/fx/frankfurter_fx_provider.dart';
import '../../infrastructure/cloud/supabase_cloud_auth_gateway.dart';
import '../../infrastructure/cloud/supabase_attachment_cloud_store.dart';
import '../../infrastructure/cloud/supabase_sync_gateway.dart';
import '../../infrastructure/cloud/supabase_vault_recovery_gateway.dart';
import '../../infrastructure/cloud/secure_supabase_local_storage.dart';
import '../../infrastructure/security/secure_string_store.dart';
import '../../infrastructure/security/attachment_cipher.dart';
import '../../infrastructure/security/encrypted_payload_cipher.dart';
import '../../infrastructure/security/vault_key_manager.dart';
import '../../infrastructure/security/vault_recovery_service.dart';
import '../../infrastructure/files/encrypted_attachment_content_store.dart';
import '../../infrastructure/files/encrypted_attachment_file_codec.dart';
import '../../infrastructure/files/equis_file_layout.dart';
import '../../infrastructure/portability/equis_backup_service.dart';
import '../../infrastructure/portability/vault_logical_snapshot_store.dart';
import '../../infrastructure/portability/vault_plaintext_exporter.dart';
import '../../infrastructure/sync/drift_sync_aggregate_store.dart';
import '../../infrastructure/sync/vault_attachment_sync.dart';
import '../../infrastructure/sync/drift_sync_metadata_store.dart';
import '../../infrastructure/sync/drift_sync_mutation_recorder.dart';
import '../../infrastructure/sync/drift_sync_enrollment_store.dart';
import '../../infrastructure/sync/cloud_sync_enrollment_service.dart';
import '../../application/services/sync_engine.dart';
import '../../application/services/sync_coordinator.dart';
import '../../application/services/sync_mutation_notifications.dart';
import '../../application/ports/sync_conflict_resolver.dart';
import '../../infrastructure/network/connectivity_plus_reachability.dart';
import '../../infrastructure/repositories/drift_ledger_repository.dart';
import '../../infrastructure/repositories/drift_credit_card_repository.dart';
import '../../infrastructure/repositories/drift_dashboard_repository.dart';
import '../../infrastructure/repositories/drift_transaction_history_repository.dart';
import '../../infrastructure/repositories/drift_cloud_identity_repository.dart';
import '../../infrastructure/repositories/drift_attachment_repository.dart';
import '../../application/ports/transaction_history_repository.dart';
import '../../application/services/recurring_transaction_service.dart';
import '../../infrastructure/repositories/drift_recurring_repository.dart';

final class LocalAppDependencies {
  const LocalAppDependencies({
    required this.lifecycle,
    required this.session,
    required this.history,
    required this.recurring,
    required this.creditCards,
    required this.dashboard,
    required this.budgets,
    required this.goals,
    required this.cashFlow,
    required this.wealth,
    required this.investments,
    required this.marketData,
    required this.fxRates,
    required this.intelligence,
    required this.cloudAccounts,
    required this.existingVaultRestore,
    required this.attachments,
    required this.backups,
    required this.plaintextExports,
    required this.vaultKeys,
    required this.syncEncryption,
    required this.attachmentEncryption,
    required this.recovery,
    required this.sync,
    required this.syncCoordinator,
    required this.syncConflicts,
    required this.syncEnrollment,
    required this._syncMutationNotifications,
  });

  final EncryptedDriftDatabaseLifecycle lifecycle;
  final LocalFinanceSessionService session;
  final TransactionHistoryRepository history;
  final RecurringTransactionService recurring;
  final CreditCardService creditCards;
  final DashboardService dashboard;
  final BudgetService budgets;
  final GoalService goals;
  final CashFlowProjectionService cashFlow;
  final WealthService wealth;
  final InvestmentService investments;
  final MarketDataService marketData;
  final FxRateSelector fxRates;
  final FinancialIntelligenceService intelligence;
  final CloudAccountService cloudAccounts;
  final ExistingVaultRestoreService? existingVaultRestore;
  final AttachmentService attachments;
  final EquisBackupService backups;
  final VaultPlaintextExporter plaintextExports;
  final VaultKeyManager vaultKeys;
  final SyncPayloadCipher syncEncryption;
  final AttachmentCipher attachmentEncryption;
  final VaultRecoveryService recovery;
  final SyncEngine? sync;
  final SyncCoordinator? syncCoordinator;
  final SyncConflictResolver syncConflicts;
  final CloudSyncEnrollmentService? syncEnrollment;
  final SyncMutationNotifications _syncMutationNotifications;

  static Future<LocalAppDependencies> bootstrap({
    Directory? profileDirectory,
    String? profileId,
    SecureStringStore? storage,
    bool cloudEnabled = true,
  }) async {
    final support = profileDirectory ?? await getApplicationSupportDirectory();
    final dataDirectory =
        profileDirectory ??
        Directory('${support.path}${Platform.pathSeparator}Equis');
    final fileLayout = EquisFileLayout(dataDirectory);
    await fileLayout.ensureCreated();
    final secureStore = storage ?? const FlutterSecureStringStore();
    final vaultKeys = profileId == null
        ? VaultKeyManager(store: secureStore)
        : VaultKeyManager(
            store: PrefixedSecureStringStore(
              secureStore,
              'equis.profiles.$profileId.vault.',
            ),
            protocolVersion: 2,
          );
    final databaseKeys = profileId == null
        ? vaultKeys
        : VaultKeyManager(
            store: PrefixedSecureStringStore(
              secureStore,
              'equis.profiles.$profileId.database.',
            ),
          );
    final lifecycle = EncryptedDriftDatabaseLifecycle(
      file: File('${dataDirectory.path}${Platform.pathSeparator}vault.db'),
      keyProvider: SecureStorageLocalDatabaseKeyProvider(
        keyManager: databaseKeys,
      ),
    );
    await lifecycle.initialize();
    final database = lifecycle.database;
    if (profileId != null) {
      final existing = await database
          .customSelect('SELECT id FROM vaults LIMIT 1')
          .getSingleOrNull();
      if (existing != null) {
        await vaultKeys.requireVault(existing.read<String>('id'));
      }
    }
    final config = AppConfig.fromEnvironment();
    final cloudAuth = cloudEnabled
        ? await _initializeCloudAuth(config, secureStore)
        : null;
    final cloudSync = profileId != null && cloudAuth is SupabaseCloudAuthGateway
        ? SupabaseSyncGateway(cloudAuth.client, keys: vaultKeys)
        : null;
    final syncMetadata = DriftSyncMetadataStore(database);
    final syncAggregates = DriftSyncAggregateStore(
      database: database,
      metadata: syncMetadata,
    );
    final syncMutationNotifications = SyncMutationNotifications();
    final syncRecorder = DriftSyncMutationRecorder(
      database: database,
      aggregates: syncAggregates,
      metadata: syncMetadata,
      notifications: syncMutationNotifications,
    );
    final recovery = VaultRecoveryService(keys: vaultKeys);
    final attachmentCipher = AttachmentCipher(keys: vaultKeys);
    final attachmentCodec = EncryptedAttachmentFileCodec(
      cipher: attachmentCipher,
    );
    final logicalSnapshots = VaultLogicalSnapshotStore(database);
    final recoveryGateway = cloudSync == null
        ? null
        : SupabaseVaultRecoveryGateway(cloudSync.client);
    final syncEnrollment = cloudSync == null
        ? null
        : CloudSyncEnrollmentService(
            cloud: cloudSync,
            recoveryGateway: recoveryGateway!,
            recovery: recovery,
            local: DriftSyncEnrollmentStore(
              database: database,
              metadata: syncMetadata,
              allowVerifiedOwnerBinding: profileId != null,
            ),
          );
    final syncCipher = SyncPayloadCipher(keys: vaultKeys);
    final attachmentService = AttachmentService(
      repository: DriftAttachmentRepository(
        database,
        syncRecorder: syncRecorder,
      ),
      content: EncryptedAttachmentContentStore(
        layout: fileLayout,
        codec: attachmentCodec,
      ),
      cloud: cloudSync == null
          ? null
          : SupabaseAttachmentCloudStore(
              cloudSync.client,
              keys: vaultKeys,
              bucket: 'equis-attachments',
            ),
    );
    final attachmentSync = VaultAttachmentSync(
      database: database,
      service: attachmentService,
      codec: attachmentCodec,
      layout: fileLayout,
    );
    final syncEngine = cloudSync == null
        ? null
        : SyncEngine(
            cloud: cloudSync,
            metadata: syncMetadata,
            aggregates: syncAggregates,
            cipher: syncCipher,
            beforePush: attachmentSync.upload,
            afterPull: attachmentSync.download,
            pullTransaction: (action) => database.transaction(() async {
              await database.customStatement('PRAGMA defer_foreign_keys = ON');
              await action();
            }),
          );
    final syncCoordinator = syncEngine == null
        ? null
        : SyncCoordinator(
            engine: syncEngine,
            wakeups: cloudSync,
            mutations: syncMutationNotifications.vaultIds,
            reachability: ConnectivityPlusReachability(),
          );
    final vaults = DriftVaultRepository(database, syncRecorder: syncRecorder);
    final currencies = DriftCurrencyRepository(database);
    final accounts = DriftAccountAggregateRepository(
      database,
      syncRecorder: syncRecorder,
    );
    final categories = DriftCategoryRepository(
      database,
      syncRecorder: syncRecorder,
    );
    final tags = DriftTagRepository(database, syncRecorder: syncRecorder);
    final ledger = DriftLedgerRepository(database, syncRecorder: syncRecorder);
    final unitOfWork = DriftLocalUnitOfWork(database);
    final recurringRepository = DriftRecurringRepository(
      database: database,
      ledger: ledger,
      syncRecorder: syncRecorder,
    );
    final creditCardRepository = DriftCreditCardRepository(
      database,
      syncRecorder: syncRecorder,
    );
    final reportingRepository = DriftDashboardRepository(database);
    final goalRepository = DriftGoalRepository(
      database,
      syncRecorder: syncRecorder,
    );
    final investmentRepository = DriftInvestmentRepository(
      database: database,
      ledger: ledger,
      syncRecorder: syncRecorder,
    );
    final investmentService = InvestmentService(
      repository: investmentRepository,
      reporting: reportingRepository,
    );
    final marketData = MarketDataService(
      instruments: investmentRepository,
      prices: DriftMarketPriceRepository(database, syncRecorder: syncRecorder),
      provider: EdgeMarketDataProvider(
        endpoint: config.cloudConfigured
            ? Uri.parse('${config.supabaseUrl}/functions/v1/market-quotes')
            : Uri(),
        publishableKey: config.supabaseAnonKey,
        accessTokenProvider: cloudAuth == null
            ? null
            : () async => cloudAuth.currentAccessToken,
      ),
    );
    final recurringService = RecurringTransactionService(
      repository: recurringRepository,
      ledger: ledger,
      unitOfWork: unitOfWork,
    );
    final dashboardService = DashboardService(
      repository: reportingRepository,
      recurring: recurringService,
    );
    final budgetService = BudgetService(
      repository: DriftBudgetRepository(database, syncRecorder: syncRecorder),
      reporting: reportingRepository,
    );
    final goalService = GoalService(
      repository: goalRepository,
      reporting: reportingRepository,
    );
    final cashFlowService = CashFlowProjectionService(
      repository: goalRepository,
      reporting: reportingRepository,
      dashboard: dashboardService,
      recurring: recurringService,
    );
    final wealthService = WealthService(
      repository: DriftWealthRepository(database, syncRecorder: syncRecorder),
      reporting: reportingRepository,
      investments: investmentService,
    );
    final intelligenceService = FinancialIntelligenceService(
      dashboard: dashboardService,
      budgets: budgetService,
      goals: goalService,
      cashFlow: cashFlowService,
      wealth: wealthService,
      investments: investmentService,
      enabled: config.localIntelligenceEnabled,
    );
    final containers = LocalFinanceContainerService(
      onVaultCreated: profileId == null
          ? null
          : (id) async {
              await vaultKeys.ensureVault(id);
            },
      vaults: vaults,
      currencies: currencies,
      accounts: accounts,
      ledger: ledger,
      unitOfWork: unitOfWork,
    );
    final taxonomy = TaxonomyService(categories: categories, tags: tags);
    final cloudAccounts = CloudAccountService(
      repository: DriftCloudIdentityRepository(database),
      auth: cloudAuth,
      deviceName: Platform.isAndroid ? 'Equis Android' : 'Equis Windows',
      platform: Platform.isAndroid ? 'android' : 'windows',
    );
    final existingVaultRestore =
        profileId != null ||
            cloudSync == null ||
            recoveryGateway == null ||
            syncCoordinator == null
        ? null
        : ExistingVaultRestoreService(
            accounts: cloudAccounts,
            discovery: recoveryGateway,
            recovery: recovery,
            lifecycle: lifecycle,
            database: database,
            cloud: cloudSync,
            coordinator: syncCoordinator,
            deviceName: Platform.isAndroid ? 'Equis Android' : 'Equis Windows',
            platform: Platform.isAndroid ? 'android' : 'windows',
          );
    return LocalAppDependencies(
      lifecycle: lifecycle,
      history: DriftTransactionHistoryRepository(
        database: database,
        ledger: ledger,
      ),
      recurring: recurringService,
      creditCards: CreditCardService(
        repository: creditCardRepository,
        ledger: ledger,
        unitOfWork: unitOfWork,
      ),
      dashboard: dashboardService,
      budgets: budgetService,
      goals: goalService,
      cashFlow: cashFlowService,
      wealth: wealthService,
      investments: investmentService,
      marketData: marketData,
      fxRates: FxRateSelector(
        manualRates: DriftManualFxRateRepository(
          database,
          syncRecorder: syncRecorder,
        ),
        cache: DriftFxRateCacheRepository(database),
        provider: FrankfurterFxProvider(),
      ),
      intelligence: intelligenceService,
      cloudAccounts: cloudAccounts,
      existingVaultRestore: existingVaultRestore,
      attachments: attachmentService,
      backups: EquisBackupService(
        snapshots: logicalSnapshots,
        attachments: attachmentCodec,
        layout: fileLayout,
      ),
      plaintextExports: VaultPlaintextExporter(logicalSnapshots),
      vaultKeys: vaultKeys,
      syncEncryption: syncCipher,
      attachmentEncryption: attachmentCipher,
      recovery: recovery,
      sync: syncEngine,
      syncCoordinator: syncCoordinator,
      syncConflicts: syncAggregates,
      syncEnrollment: syncEnrollment,
      syncMutationNotifications: syncMutationNotifications,
      session: LocalFinanceSessionService(
        vaults: vaults,
        accounts: accounts,
        categories: categories,
        tags: tags,
        ledger: ledger,
        unitOfWork: unitOfWork,
        containers: containers,
        taxonomy: taxonomy,
        everydayTransactions: EverydayTransactionService(ledger: ledger),
      ),
    );
  }

  Future<void> close() async {
    await syncCoordinator?.dispose();
    await _syncMutationNotifications.dispose();
    await lifecycle.close();
  }
}

CloudAuthGateway? _sharedCloudAuth;

Future<CloudAuthGateway?> _initializeCloudAuth(
  AppConfig config,
  SecureStringStore secureStore,
) async {
  if (!config.cloudConfigured) return null;
  if (_sharedCloudAuth != null) return _sharedCloudAuth;
  try {
    final projectRef = Uri.parse(config.supabaseUrl).host.split('.').first;
    final legacyStore = SharedPreferencesLegacyPreferenceStore();
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSupabaseLocalStorage(
          projectRef: projectRef,
          secureStore: secureStore,
          legacyStore: legacyStore,
        ),
        pkceAsyncStorage: SecureSupabasePkceStorage(
          projectRef: projectRef,
          secureStore: secureStore,
          legacyStore: legacyStore,
        ),
      ),
      debug: false,
    );
    return _sharedCloudAuth = SupabaseCloudAuthGateway(
      Supabase.instance.client,
    );
  } on Exception {
    // Cloud initialization must never prevent the encrypted local vault opening.
    return const _UnavailableCloudAuthGateway();
  }
}

final class _UnavailableCloudAuthGateway implements CloudAuthGateway {
  const _UnavailableCloudAuthGateway();

  @override
  String? get currentAccessToken => null;
  @override
  CloudAuthIdentity? get currentIdentity => null;
  @override
  Stream<CloudAuthIdentity?> get identityChanges => const Stream.empty();

  @override
  Future<void> resendVerification(String email) => _fail();
  @override
  Future<CloudAuthIdentity> signIn({
    required String email,
    required String password,
  }) => _fail();
  @override
  Future<CloudAuthIdentity> signUp({
    required String email,
    required String password,
  }) => _fail();
  @override
  Future<void> signOut() => _fail();

  Future<T> _fail<T>() =>
      Future.error(const CloudAuthFailure(CloudAuthFailureCode.network));
}

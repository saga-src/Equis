import 'dart:async';

import 'package:equis/app/router/app_router.dart';
import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/app/theme/equis_theme_controller.dart';
import 'package:equis/application/services/everyday_transaction_service.dart';
import 'package:equis/application/services/local_finance_session_service.dart';
import 'package:equis/domain/ledger/ledger_models.dart';
import 'package:equis/domain/credit_cards/credit_card_models.dart';
import 'package:equis/domain/entities/category_node.dart';
import 'package:equis/domain/entities/account_profile.dart';
import 'package:equis/domain/entities/account_aggregate.dart';
import 'package:equis/domain/shared/currency.dart';
import 'package:equis/domain/shared/decimal_value.dart';
import 'package:equis/domain/shared/local_date.dart';
import 'package:equis/domain/shared/money.dart';
import 'package:equis/domain/shared/utc_instant.dart';
import 'package:equis/domain/shared/uuid_v7.dart';
import 'package:equis/domain/taxonomy/tag.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:equis/presentation/history/transaction_history_controller.dart';
import 'package:equis/presentation/recurring/recurring_controller.dart';
import 'package:equis/presentation/credit_cards/credit_card_controller.dart';
import 'package:equis/presentation/home/dashboard_controller.dart';
import 'package:equis/presentation/budgets/budget_controller.dart';
import 'package:equis/presentation/goals/goal_controller.dart';
import 'package:equis/presentation/wealth/wealth_controller.dart';
import 'package:equis/presentation/investments/investment_controller.dart';
import 'package:equis/presentation/intelligence/financial_intelligence_controller.dart';
import 'package:equis/presentation/cloud/cloud_account_controller.dart';

import 'local_app_dependencies.dart';
import '../vault_workspace.dart';
import '../../infrastructure/settings/shared_preferences_locale_store.dart';

final vaultWorkspaceProvider = Provider<VaultWorkspace?>((ref) => null);

final appRouterProvider = Provider<GoRouter>((ref) => createAppRouter());

final localeProvider = StateProvider<Locale>((ref) => const Locale('en', 'US'));
final localePreferenceStoreProvider = Provider<SharedPreferencesLocaleStore?>(
  (ref) => null,
);

Future<void> selectAppLocale(WidgetRef ref, Locale locale) async {
  ref.read(localeProvider.notifier).state = locale;
  await ref.read(localePreferenceStoreProvider)?.save(locale);
}

final themeVariantProvider =
    StateNotifierProvider<EquisThemeController, EquisThemeVariant>(
      (ref) => EquisThemeController(),
    );

final localAppDependenciesProvider = Provider<LocalAppDependencies?>(
  (ref) => null,
);

final localFinanceControllerProvider =
    StateNotifierProvider<
      LocalFinanceController,
      AsyncValue<LocalFinanceSnapshot?>
    >((ref) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final controller = LocalFinanceController(dependencies?.session);
      final subscription = dependencies?.syncCoordinator?.results.listen((
        result,
      ) {
        if (result.pulled > 0) unawaited(controller.reload());
      });
      ref.onDispose(() => unawaited(subscription?.cancel()));
      unawaited(controller.reload());
      return controller;
    });

final transactionHistoryControllerProvider =
    StateNotifierProvider.autoDispose<
      TransactionHistoryController,
      TransactionHistoryState
    >((ref) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final vaultId = ref.watch(
        localFinanceControllerProvider.select(
          (state) => state.valueOrNull?.vault?.id,
        ),
      );
      final controller = TransactionHistoryController(
        repository: dependencies?.history,
        vaultId: vaultId,
      );
      final subscription = dependencies?.syncCoordinator?.results.listen((
        result,
      ) {
        if (result.pulled > 0) unawaited(controller.refresh());
      });
      ref.onDispose(() => unawaited(subscription?.cancel()));
      unawaited(controller.loadInitial());
      return controller;
    });

final recurringControllerProvider =
    StateNotifierProvider.autoDispose<RecurringController, RecurringState>((
      ref,
    ) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final vaultId = ref.watch(
        localFinanceControllerProvider.select(
          (state) => state.valueOrNull?.vault?.id,
        ),
      );
      final controller = RecurringController(
        service: dependencies?.recurring,
        vaultId: vaultId,
      );
      unawaited(controller.reload());
      return controller;
    });

final creditCardContextsProvider = Provider<List<CreditCardContext>>((ref) {
  final snapshot = ref.watch(localFinanceControllerProvider).valueOrNull;
  final vault = snapshot?.vault;
  if (snapshot == null || vault == null) return const [];
  return [
    for (final aggregate in snapshot.accounts)
      if (aggregate.account.type == AccountType.creditCard)
        for (final pocket in aggregate.pockets)
          CreditCardContext(
            vaultId: vault.id,
            accountId: aggregate.account.id,
            pocketId: pocket.id,
            currency: pocket.currency,
          ),
  ];
});

final creditCardControllerProvider =
    StateNotifierProvider.autoDispose<CreditCardController, CreditCardState>((
      ref,
    ) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final cards = ref.watch(creditCardContextsProvider);
      final controller = CreditCardController(
        service: dependencies?.creditCards,
        initialCard: cards.isEmpty ? null : cards.first,
        onLedgerChanged: () =>
            ref.read(localFinanceControllerProvider.notifier).reload(),
      );
      unawaited(controller.reload());
      return controller;
    });

final dashboardControllerProvider =
    StateNotifierProvider.autoDispose<DashboardController, DashboardState>((
      ref,
    ) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final vault = ref.watch(
        localFinanceControllerProvider.select(
          (state) => state.valueOrNull?.vault,
        ),
      );
      final controller = DashboardController(
        service: dependencies?.dashboard,
        vaultId: vault?.id,
        reportingCurrency: vault?.baseCurrency,
      );
      unawaited(controller.reload());
      return controller;
    });

final budgetControllerProvider =
    StateNotifierProvider.autoDispose<BudgetController, BudgetState>((ref) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final vaultId = ref.watch(
        localFinanceControllerProvider.select(
          (state) => state.valueOrNull?.vault?.id,
        ),
      );
      final controller = BudgetController(
        service: dependencies?.budgets,
        vaultId: vaultId,
      );
      unawaited(controller.reload());
      return controller;
    });

final goalControllerProvider =
    StateNotifierProvider.autoDispose<GoalController, GoalState>((ref) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final vault = ref.watch(
        localFinanceControllerProvider.select(
          (state) => state.valueOrNull?.vault,
        ),
      );
      final controller = GoalController(
        goals: dependencies?.goals,
        cashFlow: dependencies?.cashFlow,
        vaultId: vault?.id,
        reportingCurrency: vault?.baseCurrency,
      );
      unawaited(controller.reload());
      return controller;
    });

final wealthControllerProvider =
    StateNotifierProvider.autoDispose<WealthController, WealthState>((ref) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final vault = ref.watch(
        localFinanceControllerProvider.select(
          (state) => state.valueOrNull?.vault,
        ),
      );
      final controller = WealthController(
        service: dependencies?.wealth,
        vaultId: vault?.id,
        reportingCurrency: vault?.baseCurrency,
      );
      unawaited(controller.reload());
      return controller;
    });

final investmentControllerProvider =
    StateNotifierProvider.autoDispose<InvestmentController, InvestmentState>((
      ref,
    ) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final vault = ref.watch(
        localFinanceControllerProvider.select(
          (state) => state.valueOrNull?.vault,
        ),
      );
      final controller = InvestmentController(
        service: dependencies?.investments,
        market: dependencies?.marketData,
        vaultId: vault?.id,
        reportingCurrency: vault?.baseCurrency,
      );
      unawaited(controller.reload());
      return controller;
    });

final financialIntelligenceControllerProvider =
    StateNotifierProvider.autoDispose<
      FinancialIntelligenceController,
      FinancialIntelligenceState
    >((ref) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final vault = ref.watch(
        localFinanceControllerProvider.select(
          (state) => state.valueOrNull?.vault,
        ),
      );
      final controller = FinancialIntelligenceController(
        service: dependencies?.intelligence,
        vaultId: vault?.id,
        currency: vault?.baseCurrency,
      );
      unawaited(controller.reload());
      return controller;
    });

final cloudAccountControllerProvider =
    StateNotifierProvider.autoDispose<
      CloudAccountController,
      CloudAccountState
    >((ref) {
      final dependencies = ref.watch(localAppDependenciesProvider);
      final vaultId = ref.watch(
        localFinanceControllerProvider.select(
          (state) => state.valueOrNull?.vault?.id,
        ),
      );
      final controller = CloudAccountController(
        service: dependencies?.cloudAccounts,
        vaultId: vaultId,
        enrollment: dependencies?.syncEnrollment,
        syncCoordinator: dependencies?.syncCoordinator,
        conflictResolver: dependencies?.syncConflicts,
        restore: dependencies?.existingVaultRestore,
        onRestored: () =>
            ref.read(localFinanceControllerProvider.notifier).reload(),
      );
      unawaited(controller.reload());
      return controller;
    });

final class LocalFinanceController
    extends StateNotifier<AsyncValue<LocalFinanceSnapshot?>> {
  LocalFinanceController(this._session) : super(const AsyncValue.loading());

  final LocalFinanceSessionService? _session;

  Future<void> reload() async {
    if (_session == null) {
      state = const AsyncValue.data(null);
      return;
    }
    state = const AsyncValue<LocalFinanceSnapshot?>.loading().copyWithPrevious(
      state,
    );
    final loaded = await AsyncValue.guard(_session.load);
    if (mounted) state = loaded;
  }

  Future<void> setup({
    required String profileName,
    required String accountName,
    required CurrencyCode currency,
    required String locale,
    required String timezone,
  }) => _mutate(
    () => _requiredSession.setupLocalVault(
      profileName: profileName,
      accountName: accountName,
      currency: currency,
      locale: locale,
      timezone: timezone,
      now: UtcInstant.now(),
    ),
  );

  Future<void> createTransaction({
    required EverydayTransactionType type,
    required LedgerPocket source,
    required String amountText,
    required LocalDate date,
    EntityId? categoryId,
    LedgerPocket? destination,
    List<EntityId> tagIds = const [],
    String? title,
    String? notes,
  }) => _mutate(
    () => _requiredSession.createEverydayTransaction(
      type: type,
      source: source,
      destination: destination,
      amount: _money(amountText, source.currency),
      categoryId: categoryId,
      date: date,
      now: UtcInstant.now(),
      tagIds: tagIds,
      title: title,
      notes: notes,
    ),
  );

  Future<void> updateTransaction({
    required LedgerTransaction existing,
    required LedgerPocket source,
    required String amountText,
    required LocalDate date,
    EntityId? categoryId,
    LedgerPocket? destination,
    List<EntityId> tagIds = const [],
    String? title,
    String? notes,
  }) => _mutate(
    () => _requiredSession.updateEverydayTransaction(
      existing: existing,
      source: source,
      destination: destination,
      amount: _money(amountText, source.currency),
      categoryId: categoryId,
      date: date,
      now: UtcInstant.now(),
      tagIds: tagIds,
      title: title,
      notes: notes,
    ),
  );

  Future<void> deleteTransaction(LedgerTransaction transaction) => _mutate(
    () =>
        _requiredSession.deleteTransaction(transaction, now: UtcInstant.now()),
  );

  Future<void> reconcileTransaction(LedgerTransaction transaction) => _mutate(
    () => _requiredSession.reconcileTransaction(
      transaction,
      now: UtcInstant.now(),
    ),
  );

  Future<void> createCategory({
    required CategoryType type,
    required String name,
    String? nameEnUs,
    String? namePtBr,
    EntityId? parentId,
  }) => _mutate(
    () => _requiredSession.createCategory(
      type: type,
      name: name,
      nameEnUs: nameEnUs,
      namePtBr: namePtBr,
      parentId: parentId,
      now: UtcInstant.now(),
    ),
  );

  Future<void> archiveCategory(CategoryNode category) => _mutate(
    () => _requiredSession.archiveCategory(category, now: UtcInstant.now()),
  );

  Future<void> createTag({
    required String name,
    String? nameEnUs,
    String? namePtBr,
    String? color,
  }) => _mutate(
    () => _requiredSession.createTag(
      name: name,
      nameEnUs: nameEnUs,
      namePtBr: namePtBr,
      color: color,
      now: UtcInstant.now(),
    ),
  );

  Future<void> updateCategoryNames({
    required CategoryNode category,
    required String name,
    String? nameEnUs,
    String? namePtBr,
  }) => _mutate(
    () => _requiredSession.updateCategoryNames(
      category: category,
      name: name,
      nameEnUs: nameEnUs,
      namePtBr: namePtBr,
      now: UtcInstant.now(),
    ),
  );

  Future<void> updateTagNames({
    required Tag tag,
    required String name,
    String? nameEnUs,
    String? namePtBr,
  }) => _mutate(
    () => _requiredSession.updateTagNames(
      tag: tag,
      name: name,
      nameEnUs: nameEnUs,
      namePtBr: namePtBr,
      now: UtcInstant.now(),
    ),
  );

  Future<void> createAccount({
    required String name,
    required AccountType type,
    required AccountNature nature,
    required CurrencyCode currency,
  }) => _mutate(
    () => _requiredSession.createAccount(
      name: name,
      type: type,
      nature: nature,
      currency: currency,
      now: UtcInstant.now(),
    ),
  );

  Future<void> setAccountNetWorthInclusion(
    AccountAggregate account,
    bool included,
  ) => _mutate(
    () => _requiredSession.setAccountNetWorthInclusion(
      account,
      included,
      now: UtcInstant.now(),
    ),
  );

  LocalFinanceSessionService get _requiredSession =>
      _session ?? (throw StateError('Local services are not available.'));

  Future<void> _mutate(Future<LocalFinanceSnapshot> Function() action) async {
    final previous = state.valueOrNull;
    state = const AsyncValue<LocalFinanceSnapshot?>.loading().copyWithPrevious(
      state,
    );
    try {
      state = AsyncValue.data(await action());
    } catch (error, stackTrace) {
      state = AsyncValue.data(previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Money _money(String input, CurrencyCode currency) {
    final normalized = _normalizeDecimal(input);
    final major = DecimalValue.parse(normalized);
    if (major <= Decimal.zero) {
      throw ArgumentError('Transaction amount must be positive.');
    }
    return Money.fromMajor(
      currency: CurrencyDefinition(code: currency, minorUnits: 2),
      majorUnits: major,
    );
  }

  String _normalizeDecimal(String input) {
    var value = input.trim().replaceAll(RegExp(r'\s'), '');
    final comma = value.lastIndexOf(',');
    final dot = value.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      value = comma > dot
          ? value.replaceAll('.', '').replaceAll(',', '.')
          : value.replaceAll(',', '');
    } else if (comma >= 0) {
      value = value.replaceAll(',', '.');
    }
    return value;
  }
}

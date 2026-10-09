import '../../presentation/cloud/vault_hub_screen.dart';
import '../providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/ledger/transaction_search.dart';
import 'package:equis/presentation/home/local_finance_home_screen.dart';
import 'package:equis/presentation/history/transaction_history_screen.dart';
import 'package:equis/presentation/recurring/recurring_screen.dart';
import 'package:equis/presentation/credit_cards/credit_card_screen.dart';
import 'package:equis/presentation/accounts/account_management_page.dart';
import 'package:equis/presentation/budgets/budget_screen.dart';
import 'package:equis/presentation/goals/goal_screen.dart';
import 'package:equis/presentation/wealth/wealth_screen.dart';
import 'package:equis/presentation/investments/investment_screen.dart';
import 'package:equis/presentation/intelligence/financial_intelligence_screen.dart';
import 'package:equis/presentation/cloud/cloud_account_screen.dart';
import 'package:equis/presentation/settings/settings_screen.dart';
import 'package:equis/presentation/settings/taxonomy_screen.dart';
import 'package:equis/presentation/settings/portability_screen.dart';
import 'package:equis/presentation/shell/equis_shell.dart';
import 'package:equis/presentation/transactions/local_transaction_page.dart';
import 'package:equis/presentation/transactions/transaction_detail_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/guide/getting_started_screen.dart';
import '../../presentation/guide/welcome_screen.dart';
import '../../presentation/shared/vault_required.dart';

GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            EquisShell(currentLocation: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                _tabPage(state, const LocalFinanceHomeScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _tabPage(state, const SettingsScreen()),
          ),
          GoRoute(
            path: '/history',
            pageBuilder: (context, state) => _vaultTabPage(
              state,
              TransactionHistoryScreen(
                initialFilter: state.extra is TransactionSearchFilter
                    ? state.extra as TransactionSearchFilter
                    : null,
              ),
            ),
          ),
          GoRoute(
            path: '/recurring',
            pageBuilder: (context, state) =>
                _vaultTabPage(state, const RecurringScreen()),
          ),
          GoRoute(
            path: '/cards',
            pageBuilder: (context, state) => _vaultTabPage(
              state,
              CreditCardScreen(
                onManageSelectedCard: (accountId) => context.push(
                  '/accounts?selected=${Uri.encodeQueryComponent(accountId.value)}',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => VaultRequired(
              child: AccountManagementPage(
                initialAccountId: state.uri.queryParameters['selected'],
              ),
            ),
          ),
          GoRoute(
            path: '/budgets',
            pageBuilder: (context, state) =>
                _vaultTabPage(state, const BudgetScreen()),
          ),
          GoRoute(
            path: '/goals',
            pageBuilder: (context, state) =>
                _vaultTabPage(state, const GoalScreen()),
          ),
          GoRoute(
            path: '/wealth',
            pageBuilder: (context, state) =>
                _vaultTabPage(state, const WealthScreen()),
          ),
          GoRoute(
            path: '/investments',
            pageBuilder: (context, state) =>
                _vaultTabPage(state, const InvestmentScreen()),
          ),
          GoRoute(
            path: '/intelligence',
            pageBuilder: (context, state) =>
                _vaultTabPage(state, const FinancialIntelligenceScreen()),
          ),
          GoRoute(
            path: '/vault-sync',
            builder: (context, state) =>
                const VaultRequired(child: CloudAccountScreen()),
          ),
          GoRoute(
            path: '/cloud-account',
            builder: (context, state) => Consumer(
              builder: (context, ref, _) =>
                  ref.watch(vaultWorkspaceProvider) == null
                  ? const CloudAccountScreen()
                  : const VaultHubScreen(),
            ),
          ),
          GoRoute(
            path: '/taxonomy',
            builder: (context, state) =>
                const VaultRequired(child: TaxonomyScreen()),
          ),
          GoRoute(
            path: '/portability',
            builder: (context, state) => const PortabilityScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/transactions/new',
        builder: (context, state) =>
            const VaultRequired(child: LocalTransactionPage()),
      ),
      GoRoute(
        path: '/guide',
        builder: (context, state) => const GettingStartedScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/transactions/:id/details',
        builder: (context, state) => VaultRequired(
          child: TransactionDetailScreen(
            transactionId: state.pathParameters['id'],
          ),
        ),
      ),
      GoRoute(
        path: '/transactions/:id',
        builder: (context, state) => VaultRequired(
          child: LocalTransactionPage(
            transactionId: state.pathParameters['id'],
          ),
        ),
      ),
    ],
  );
}

NoTransitionPage<void> _tabPage(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

NoTransitionPage<void> _vaultTabPage(GoRouterState state, Widget child) =>
    _tabPage(state, VaultRequired(child: child));

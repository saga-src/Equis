import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers/app_providers.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../shared/equis_glass.dart';

class GettingStartedScreen extends ConsumerWidget {
  const GettingStartedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hasVault =
        ref.watch(localFinanceControllerProvider).valueOrNull?.vault != null;
    final topics = <(IconData, String, String, String)>[
      (
        Icons.lock_outline,
        l10n.guideVaultsTitle,
        l10n.guideVaultsBody,
        hasVault ? '/cloud-account' : '/',
      ),
      (
        Icons.account_balance_outlined,
        l10n.accountManagementTitle,
        l10n.guideAccountsBody,
        '/accounts',
      ),
      (
        Icons.receipt_long_outlined,
        l10n.guideTransactionsTitle,
        l10n.guideTransactionsBody,
        '/transactions/new',
      ),
      (
        Icons.category_outlined,
        l10n.manageCategoriesTagsAction,
        l10n.guideCategoriesBody,
        '/taxonomy',
      ),
      (
        Icons.repeat,
        l10n.recurringTitle,
        l10n.guideRecurringBody,
        '/recurring',
      ),
      (
        Icons.savings_outlined,
        l10n.budgetsNavigationLabel,
        l10n.guideBudgetsBody,
        '/budgets',
      ),
      (
        Icons.insights_outlined,
        l10n.reportsSectionTitle,
        l10n.guideReportsBody,
        '/',
      ),
      (
        Icons.backup_outlined,
        l10n.portabilityTitle,
        l10n.guideBackupBody,
        '/portability',
      ),
      (Icons.sync, l10n.guideSyncTitle, l10n.guideSyncBody, '/vault-sync'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.gettingStartedGuideTitle),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l10n.guideIntroBody),
          if (!hasVault) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('guide-create-vault'),
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.add),
                label: Text(l10n.createLocalVaultAction),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (ref.watch(localAppDependenciesProvider)?.experience != null)
            TextButton(
              onPressed: () async {
                final dependencies = ref.read(localAppDependenciesProvider)!;
                try {
                  await dependencies.experience!.setChecklistHidden(
                    dependencies.profileId,
                    false,
                  );
                  ref.invalidate(gettingStartedStatusProvider);
                  if (context.mounted) context.go('/');
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.experiencePreferenceFailedMessage),
                      ),
                    );
                  }
                }
              },
              child: Text(l10n.checklistShowAction),
            ),
          for (final topic in topics)
            EquisGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(topic.$1),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            topic.$2,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(topic.$3),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.go(topic.$4),
                      child: Text(l10n.guideOpenAction),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/app_providers.dart';
import '../../application/services/getting_started_service.dart';
import '../../l10n/app_localizations.dart';
import '../shared/equis_glass.dart';

class GettingStartedChecklist extends ConsumerWidget {
  const GettingStartedChecklist({super.key, this.statusOverride, this.onHide});
  final GettingStartedStatus? statusOverride;
  final Future<void> Function()? onHide;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status =
        statusOverride ?? ref.watch(gettingStartedStatusProvider).valueOrNull;
    if (status == null || status.hidden) return const SizedBox.shrink();
    final items = <(String, bool, String)>[
      (l10n.checklistAccountLabel, status.facts.hasAccount, '/accounts'),
      (
        l10n.checklistTransactionLabel,
        status.facts.hasTransaction,
        '/transactions/new',
      ),
      (l10n.checklistBudgetLabel, status.facts.hasBudget, '/budgets'),
      (l10n.checklistBackupLabel, status.backupCreated, '/portability'),
    ];
    return EquisGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.gettingStartedChecklistTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (status.complete) Text(l10n.checklistCompleteMessage),
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  item.$2
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                ),
                title: Text(item.$1),
                subtitle: Text(
                  item.$2
                      ? l10n.checklistDoneLabel
                      : l10n.checklistPendingLabel,
                ),
                onTap: () => context.push(item.$3),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => context.push('/guide'),
                  child: Text(l10n.gettingStartedGuideTitle),
                ),
                TextButton(
                  key: const Key('checklist-hide'),
                  onPressed: () async {
                    final dependencies = ref.read(localAppDependenciesProvider);
                    try {
                      if (onHide != null) {
                        await onHide!();
                      } else {
                        await dependencies?.experience?.setChecklistHidden(
                          dependencies.profileId,
                          true,
                        );
                      }
                      ref.invalidate(gettingStartedStatusProvider);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.experiencePreferenceFailedMessage,
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(l10n.checklistHideAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

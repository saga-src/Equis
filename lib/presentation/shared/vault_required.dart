import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/app_providers.dart';
import '../../l10n/app_localizations.dart';

/// Keeps vault-dependent pages unmounted until a vault is available.
class VaultRequired extends ConsumerWidget {
  const VaultRequired({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finance = ref.watch(localFinanceControllerProvider);
    if (finance.valueOrNull?.vault != null) return child;
    final l = AppLocalizations.of(context);
    return finance.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l.appTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: Text(l.appTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.localVaultErrorMessage, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref
                      .read(localFinanceControllerProvider.notifier)
                      .reload(),
                  child: Text(l.transactionDetailRetryAction),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (_) => Scaffold(
        appBar: AppBar(title: Text(l.vaultRequiredTitle)),
        body: const Center(child: VaultRequiredNotice()),
      ),
    );
  }
}

class VaultRequiredNotice extends StatelessWidget {
  const VaultRequiredNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline, size: 40),
            const SizedBox(height: 16),
            Text(
              l.vaultRequiredTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(l.setupRequiredMessage),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('vault-required-create'),
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.add),
                  label: Text(l.createLocalVaultAction),
                ),
                TextButton(
                  key: const Key('vault-required-open'),
                  onPressed: () => context.go('/cloud-account'),
                  child: Text(l.vaultOpenAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

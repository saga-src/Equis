import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/shared/equis_glass.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: null,
        icon: const Icon(Icons.add),
        label: Text(l10n.addTransactionAction),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            l10n.availableMoneyTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          EquisGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('—', style: EquisTypography.numeric),
                  const SizedBox(height: 8),
                  Text(l10n.availableMoneyPlaceholder),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          EquisGlassCard(
            child: ListTile(
              leading: const Icon(Icons.offline_bolt_outlined),
              title: Text(l10n.foundationStatusTitle),
              subtitle: Text(l10n.foundationStatusBody),
              trailing: Chip(label: Text(l10n.offlineReadyLabel)),
            ),
          ),
        ],
      ),
    );
  }
}

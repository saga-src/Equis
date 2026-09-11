import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/shared/equis_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'update_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final themeVariant = ref.watch(themeVariantProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsNavigationLabel)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const UpdateCard(),
          if (ref.watch(vaultWorkspaceProvider) != null)
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(l10n.vaultsTitle),
              onTap: () => context.push('/cloud-account'),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ModuleLink(
                icon: Icons.savings_outlined,
                label: l10n.budgetsNavigationLabel,
                route: '/budgets',
              ),
              _ModuleLink(
                icon: Icons.flag_outlined,
                label: l10n.goalsNavigationLabel,
                route: '/goals',
              ),
              _ModuleLink(
                icon: Icons.account_balance_outlined,
                label: l10n.wealthNavigationLabel,
                route: '/wealth',
              ),
              _ModuleLink(
                icon: Icons.show_chart_outlined,
                label: l10n.investmentsNavigationLabel,
                route: '/investments',
              ),
            ],
          ),
          const SizedBox(height: 16),
          EquisGlassCard(
            child: ListTile(
              key: const Key('taxonomy-settings'),
              leading: const Icon(Icons.category_outlined),
              title: Text(l10n.manageCategoriesTagsAction),
              subtitle: Text(l10n.manageCategoriesTagsSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/taxonomy'),
            ),
          ),
          const SizedBox(height: 12),
          EquisGlassCard(
            child: ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(l10n.cloudAccountTitle),
              subtitle: Text(l10n.cloudAccountSettingsSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/cloud-account'),
            ),
          ),
          const SizedBox(height: 12),
          EquisGlassCard(
            child: ListTile(
              key: const Key('portability-settings'),
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(l10n.portabilityTitle),
              subtitle: Text(l10n.portabilitySubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/portability'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.appearanceTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          EquisGlassCard(
            child: Column(
              children: [
                for (final variant in EquisThemeVariant.values) ...[
                  ListTile(
                    key: Key('theme-${variant.storageValue}'),
                    leading: Icon(_themeIcon(variant)),
                    title: Text(_themeName(l10n, variant)),
                    subtitle: Text(_themeDescription(l10n, variant)),
                    trailing: Icon(
                      themeVariant == variant
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                    ),
                    selected: themeVariant == variant,
                    onTap: themeVariant == variant
                        ? null
                        : () => ref
                              .read(themeVariantProvider.notifier)
                              .select(variant),
                  ),
                  if (variant != EquisThemeVariant.values.last)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.languageTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Column(
            children: [
              ListTile(
                key: const Key('language-en-US'),
                leading: Icon(
                  locale.languageCode == 'en'
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: Text(l10n.englishLanguage),
                onTap: locale.languageCode == 'en'
                    ? null
                    : () => selectAppLocale(ref, const Locale('en', 'US')),
              ),
              ListTile(
                key: const Key('language-pt-BR'),
                leading: Icon(
                  locale.languageCode == 'pt'
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: Text(l10n.portugueseLanguage),
                onTap: locale.languageCode == 'pt'
                    ? null
                    : () => selectAppLocale(ref, const Locale('pt', 'BR')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _themeIcon(EquisThemeVariant variant) => switch (variant) {
    EquisThemeVariant.obsidian => Icons.dark_mode_outlined,
    EquisThemeVariant.trueLight => Icons.light_mode_outlined,
    EquisThemeVariant.legacy => Icons.history_outlined,
  };

  String _themeName(AppLocalizations l10n, EquisThemeVariant variant) =>
      switch (variant) {
        EquisThemeVariant.obsidian => l10n.themeObsidianName,
        EquisThemeVariant.trueLight => l10n.themeTrueLightName,
        EquisThemeVariant.legacy => l10n.themeLegacyName,
      };

  String _themeDescription(AppLocalizations l10n, EquisThemeVariant variant) =>
      switch (variant) {
        EquisThemeVariant.obsidian => l10n.themeObsidianDescription,
        EquisThemeVariant.trueLight => l10n.themeTrueLightDescription,
        EquisThemeVariant.legacy => l10n.themeLegacyDescription,
      };
}

final class _ModuleLink extends StatelessWidget {
  const _ModuleLink({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    height: 64,
    child: OutlinedButton.icon(
      onPressed: () => context.go(route),
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}

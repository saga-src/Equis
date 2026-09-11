import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/shared/equis_glass.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EquisShell extends StatelessWidget {
  const EquisShell({
    required this.currentLocation,
    required this.child,
    super.key,
  });

  final String currentLocation;
  final Widget child;

  int get _selectedIndex => switch (currentLocation) {
    '/history' => 1,
    '/recurring' => 2,
    '/cards' => 3,
    '/budgets' => 4,
    '/goals' => 5,
    '/wealth' => 6,
    '/investments' => 7,
    '/settings' || '/taxonomy' => 8,
    _ => 0,
  };

  void _navigate(BuildContext context, int index) {
    context.go(switch (index) {
      0 => '/',
      1 => '/history',
      2 => '/recurring',
      3 => '/cards',
      4 => '/budgets',
      5 => '/goals',
      6 => '/wealth',
      7 => '/investments',
      _ => '/settings',
    });
  }

  int get _selectedMobileIndex => switch (_selectedIndex) {
    0 => 0,
    1 => 1,
    2 => 2,
    3 => 3,
    _ => 4,
  };

  void _navigateMobile(BuildContext context, int index) {
    context.go(switch (index) {
      0 => '/',
      1 => '/history',
      2 => '/recurring',
      3 => '/cards',
      _ => '/settings',
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: l10n.homeNavigationLabel,
      ),
      NavigationDestination(
        icon: const Icon(Icons.receipt_long_outlined),
        selectedIcon: const Icon(Icons.receipt_long),
        label: l10n.historyNavigationLabel,
      ),
      NavigationDestination(
        icon: const Icon(Icons.event_repeat_outlined),
        selectedIcon: const Icon(Icons.event_repeat),
        label: l10n.recurringNavigationLabel,
      ),
      NavigationDestination(
        icon: const Icon(Icons.credit_card_outlined),
        selectedIcon: const Icon(Icons.credit_card),
        label: l10n.cardsNavigationLabel,
      ),
      NavigationDestination(
        icon: const Icon(Icons.savings_outlined),
        selectedIcon: const Icon(Icons.savings),
        label: l10n.budgetsNavigationLabel,
      ),
      NavigationDestination(
        icon: const Icon(Icons.flag_outlined),
        selectedIcon: const Icon(Icons.flag),
        label: l10n.goalsNavigationLabel,
      ),
      NavigationDestination(
        icon: const Icon(Icons.account_balance_outlined),
        selectedIcon: const Icon(Icons.account_balance),
        label: l10n.wealthNavigationLabel,
      ),
      NavigationDestination(
        icon: const Icon(Icons.show_chart_outlined),
        selectedIcon: const Icon(Icons.show_chart),
        label: l10n.investmentsNavigationLabel,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.settingsNavigationLabel,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          return Scaffold(
            body: Row(
              children: [
                EquisGlassSurface(
                  child: NavigationRail(
                    scrollable: true,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/branding/logo.png',
                        width: 48,
                        height: 48,
                        cacheWidth: 96,
                        semanticLabel: 'Equis',
                      ),
                    ),
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) => _navigate(context, index),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final destination in destinations)
                        NavigationRailDestination(
                          icon: destination.icon,
                          selectedIcon: destination.selectedIcon,
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          );
        }

        return Scaffold(
          body: child,
          bottomNavigationBar: EquisGlassSurface(
            child: NavigationBar(
              selectedIndex: _selectedMobileIndex,
              onDestinationSelected: (index) => _navigateMobile(context, index),
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [...destinations.take(4), destinations.last],
            ),
          ),
        );
      },
    );
  }
}

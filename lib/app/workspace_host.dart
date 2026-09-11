import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'equis_app.dart';
import '../infrastructure/updates/app_update_service.dart';
import '../presentation/settings/update_card.dart';
import 'providers/app_providers.dart';
import 'router/app_router.dart';
import 'vault_workspace.dart';
import 'theme/equis_theme.dart';
import 'theme/equis_theme_controller.dart';
import '../infrastructure/settings/shared_preferences_theme_store.dart';
import '../infrastructure/settings/shared_preferences_locale_store.dart';

class WorkspaceHost extends StatefulWidget {
  const WorkspaceHost({
    super.key,
    required this.workspace,
    required this.initialLocale,
    required this.initialTheme,
    this.themeStore,
    this.localeStore,
    this.updateService,
  });
  final VaultWorkspace workspace;
  final Locale initialLocale;
  final EquisThemeVariant initialTheme;
  final SharedPreferencesThemeStore? themeStore;
  final SharedPreferencesLocaleStore? localeStore;
  final AppUpdateService? updateService;
  @override
  State<WorkspaceHost> createState() => _WorkspaceHostState();
}

class _WorkspaceHostState extends State<WorkspaceHost> {
  late ProviderContainer _container;
  late int _generation;
  final _retired = <ProviderContainer>[];
  @override
  void initState() {
    super.initState();
    _generation = widget.workspace.generation;
    _container = _create(widget.initialLocale, widget.initialTheme);
    widget.workspace.addListener(_changed);
    widget.workspace.awaitScopeDisposal = () async {
      await WidgetsBinding.instance.endOfFrame;
      _disposeRetired();
    };
  }

  ProviderContainer _create(Locale locale, EquisThemeVariant theme) =>
      ProviderContainer(
        overrides: [
          appUpdateServiceProvider.overrideWithValue(widget.updateService),
          vaultWorkspaceProvider.overrideWithValue(widget.workspace),
          localAppDependenciesProvider.overrideWithValue(
            widget.workspace.active,
          ),
          localeProvider.overrideWith((ref) => locale),
          localePreferenceStoreProvider.overrideWithValue(widget.localeStore),
          themeVariantProvider.overrideWith(
            (ref) => EquisThemeController(
              initialTheme: theme,
              preferenceStore: widget.themeStore,
            ),
          ),
          appRouterProvider.overrideWith((ref) {
            final router = createAppRouter();
            ref.onDispose(router.dispose);
            return router;
          }),
        ],
      );
  void _changed() {
    if (_generation != widget.workspace.generation) {
      final previous = _container;
      _container = _create(
        previous.read(localeProvider),
        previous.read(themeVariantProvider),
      );
      _retired.add(previous);
      _generation = widget.workspace.generation;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _disposeRetired() {
    for (final container in _retired) {
      container.dispose();
    }
    _retired.clear();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    key: ValueKey(_generation),
    container: _container,
    child: Stack(
      textDirection: TextDirection.ltr,
      children: [
        const EquisApp(),
        if (widget.workspace.busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x99000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    ),
  );
  @override
  void dispose() {
    widget.workspace.removeListener(_changed);
    widget.workspace.awaitScopeDisposal = null;
    _disposeRetired();
    _container.dispose();
    super.dispose();
  }
}

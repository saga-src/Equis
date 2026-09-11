import 'package:equis/app/providers/app_providers.dart';
import 'package:equis/app/theme/equis_theme.dart';
import 'package:equis/l10n/app_localizations.dart';
import 'package:equis/presentation/shared/equis_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EquisApp extends ConsumerStatefulWidget {
  const EquisApp({super.key});

  @override
  ConsumerState<EquisApp> createState() => _EquisAppState();
}

final class _EquisAppState extends ConsumerState<EquisApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(localAppDependenciesProvider)?.syncCoordinator?.onResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);
    final themeVariant = ref.watch(themeVariantProvider);
    final theme = EquisTheme.forVariant(themeVariant);
    ref.watch(cloudAccountControllerProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: theme,
      darkTheme: theme,
      themeMode: theme.brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 300),
      themeAnimationCurve: Curves.easeInOut,
      builder: (context, child) =>
          EquisThemeBackdrop(child: child ?? const SizedBox.shrink()),
      routerConfig: router,
    );
  }
}

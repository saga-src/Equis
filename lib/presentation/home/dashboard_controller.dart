import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/services/dashboard_service.dart';
import '../../application/ports/local_experience_preferences.dart';
import '../../domain/reporting/dashboard_models.dart';
import '../../domain/shared/currency.dart';
import '../../domain/shared/local_date.dart';
import '../../domain/shared/uuid_v7.dart';

final class DashboardState {
  const DashboardState({
    this.snapshot,
    this.loading = false,
    this.error,
    this.selection = const DashboardSelection(),
    this.preferenceError,
    this.invalidSelection = false,
  });
  final DashboardSnapshot? snapshot;
  final bool loading;
  final Object? error;
  final DashboardSelection selection;
  final Object? preferenceError;
  final bool invalidSelection;
}

typedef DashboardLoader =
    Future<DashboardSnapshot> Function(
      DashboardDateRange range,
      LocalDate asOf,
    );

final class DashboardController extends StateNotifier<DashboardState> {
  DashboardController({
    required DashboardService? service,
    required EntityId? vaultId,
    required CurrencyCode? reportingCurrency,
    this.preferences,
    this.profileId = 'legacy',
    DateTime Function()? clock,
    DashboardLoader? loader,
  }) : _clock = clock ?? DateTime.now,
       _load =
           loader ??
           (service == null || vaultId == null || reportingCurrency == null
               ? null
               : ((range, asOf) => service.load(
                   vaultId: vaultId,
                   reportingCurrency: reportingCurrency,
                   asOf: asOf,
                   range: range,
                 ))),
       super(const DashboardState());
  final DashboardLoader? _load;
  final DateTime Function() _clock;
  final LocalExperiencePreferences? preferences;
  final String profileId;
  int _generation = 0;
  int _selectionGeneration = 0;
  bool _initialized = false;
  Future<void> _writes = Future.value();

  LocalDate get today {
    final now = _clock();
    return LocalDate(now.year, now.month, now.day);
  }

  Future<void> reload() async {
    final generation = ++_generation;
    final selectionGeneration = _selectionGeneration;
    if (!_initialized) {
      _initialized = true;
      try {
        final saved = await preferences?.readProfile(profileId);
        if (!mounted || generation != _generation) return;
        if (saved != null && selectionGeneration == _selectionGeneration) {
          try {
            saved.dashboard.resolve(today);
            state = DashboardState(
              snapshot: state.snapshot,
              selection: saved.dashboard,
            );
          } catch (_) {
            state = DashboardState(
              snapshot: state.snapshot,
              invalidSelection: true,
            );
          }
        }
      } catch (error) {
        if (!mounted || generation != _generation) return;
        state = DashboardState(
          snapshot: state.snapshot,
          selection: state.selection,
          preferenceError: error,
        );
      }
    }
    final load = _load;
    if (load == null || !mounted || generation != _generation) return;
    final selection = state.selection;
    final asOf = today;
    state = DashboardState(
      snapshot: state.snapshot,
      loading: true,
      selection: selection,
      preferenceError: state.preferenceError,
      invalidSelection: state.invalidSelection,
    );
    try {
      final snapshot = await load(selection.resolve(asOf), asOf);
      if (!mounted || generation != _generation) return;
      state = DashboardState(
        snapshot: snapshot,
        selection: selection,
        preferenceError: state.preferenceError,
        invalidSelection: state.invalidSelection,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = DashboardState(
        snapshot: state.snapshot,
        error: error,
        selection: selection,
        preferenceError: state.preferenceError,
        invalidSelection: state.invalidSelection,
      );
    }
  }

  Future<void> select(DashboardSelection selection) async {
    selection.resolve(today);
    final selectionGeneration = ++_selectionGeneration;
    ++_generation;
    state = DashboardState(selection: selection);
    final saving = _writes.then(
      (_) async => preferences?.saveDashboard(profileId, selection),
    );
    _writes = saving.catchError((Object _) {});
    final reading = reload();
    try {
      await saving;
    } catch (error) {
      if (mounted && selectionGeneration == _selectionGeneration) {
        state = DashboardState(
          snapshot: state.snapshot,
          loading: state.loading,
          error: state.error,
          selection: state.selection,
          preferenceError: error,
        );
      }
    }
    await reading;
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}

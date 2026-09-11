import 'dart:io';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/shared/uuid_v7.dart';

import '../app/providers/local_app_dependencies.dart';
import '../application/services/sync_engine.dart';
import '../domain/cloud/cloud_identity_models.dart';
import '../domain/shared/local_date.dart';
import '../domain/shared/utc_instant.dart';

abstract final class AndroidBackgroundJobNames {
  static const pendingSync = 'equis.pending-sync';
  static const attachmentUpload = 'equis.attachment-upload';
  static const fxRefresh = 'equis.fx-refresh';
  static const marketRefresh = 'equis.market-refresh';
  static const maintenance = 'equis.maintenance';
}

@pragma('vm:entry-point')
void equisBackgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    LocalAppDependencies? dependencies;
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/Equis');
      final catalog = File('${root.path}/vault-catalog.json');
      if (!await catalog.exists()) return true;
      final data = jsonDecode(await catalog.readAsString()) as Map;
      if (data['version'] != 2) return false;
      final profile = data['active'] as String?;
      if (profile == null || profile == 'legacy') return true;
      EntityId.parse(profile);
      final directory = Directory('${root.path}/profiles/$profile');
      if (!await File('${directory.path}/vault.db').exists()) return false;
      dependencies = await LocalAppDependencies.bootstrap(
        profileDirectory: directory,
        profileId: profile,
      );
      return await AndroidBackgroundJobRunner(dependencies).run(taskName);
    } catch (_) {
      return false;
    } finally {
      await dependencies?.close();
    }
  });
}

final class AndroidBackgroundJobs {
  const AndroidBackgroundJobs._();

  static Future<void> initializeAndSchedule() async {
    if (!Platform.isAndroid) return;
    final manager = Workmanager();
    await manager.initialize(equisBackgroundCallbackDispatcher);
    final network = Constraints(networkType: NetworkType.connected);
    await _periodic(
      manager,
      AndroidBackgroundJobNames.pendingSync,
      const Duration(minutes: 15),
      network,
    );
    await _periodic(
      manager,
      AndroidBackgroundJobNames.attachmentUpload,
      const Duration(minutes: 15),
      network,
    );
    await _periodic(
      manager,
      AndroidBackgroundJobNames.fxRefresh,
      const Duration(hours: 6),
      network,
    );
    await _periodic(
      manager,
      AndroidBackgroundJobNames.marketRefresh,
      const Duration(hours: 6),
      network,
    );
    await _periodic(
      manager,
      AndroidBackgroundJobNames.maintenance,
      const Duration(hours: 24),
      Constraints(requiresBatteryNotLow: true, requiresStorageNotLow: true),
    );
  }

  static Future<void> _periodic(
    Workmanager manager,
    String name,
    Duration frequency,
    Constraints constraints,
  ) => manager.registerPeriodicTask(
    name,
    name,
    frequency: frequency,
    constraints: constraints,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
    tag: 'equis-opportunistic-background',
  );
}

final class AndroidBackgroundJobRunner {
  const AndroidBackgroundJobRunner(this.dependencies);

  final LocalAppDependencies dependencies;

  Future<bool> run(String taskName) async {
    final snapshot = await dependencies.session.load();
    final vault = snapshot.vault;
    if (vault == null) return true;
    final now = UtcInstant.now();
    final dateTime = now.toDateTime();
    final today = LocalDate(dateTime.year, dateTime.month, dateTime.day);

    switch (taskName) {
      case AndroidBackgroundJobNames.pendingSync:
        final account = await dependencies.cloudAccounts.load(
          vaultId: vault.id,
          now: now,
        );
        final coordinator = dependencies.syncCoordinator;
        if (account.status != CloudAccountStatus.signedIn ||
            account.binding?.syncEnabled != true ||
            coordinator == null) {
          return true;
        }
        final result = await coordinator.start(
          vaultId: vault.id.value,
          deviceId: account.device.id.value,
        );
        return result.status == SyncRunStatus.succeeded;
      case AndroidBackgroundJobNames.attachmentUpload:
        return dependencies.attachments.uploadPendingForVault(vault.id);
      case AndroidBackgroundJobNames.fxRefresh:
        final currencies = {
          for (final account in snapshot.accounts)
            for (final pocket in account.pockets) pocket.currency,
        }..remove(vault.baseCurrency);
        for (final currency in currencies) {
          await dependencies.fxRates.select(
            vaultId: vault.id,
            base: vault.baseCurrency,
            quote: currency,
            date: today,
          );
        }
        return true;
      case AndroidBackgroundJobNames.marketRefresh:
        final states = await dependencies.marketData.load(
          vaultId: vault.id,
          asOf: today,
          now: now,
          refresh: true,
        );
        return states.every((state) => !state.refreshFailed);
      case AndroidBackgroundJobNames.maintenance:
        await dependencies.lifecycle.database.verifyIntegrity();
        await dependencies.lifecycle.database.customStatement(
          'PRAGMA optimize',
        );
        await dependencies.lifecycle.database.customStatement(
          'PRAGMA wal_checkpoint(PASSIVE)',
        );
        return true;
      default:
        return false;
    }
  }
}

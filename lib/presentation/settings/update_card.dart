import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers/app_providers.dart';
import '../../infrastructure/updates/app_update_service.dart';
import '../../infrastructure/updates/update_installer.dart';
import '../../l10n/app_localizations.dart';

final appUpdateServiceProvider = Provider<AppUpdateService?>((ref) => null);

class UpdateCard extends ConsumerWidget {
  const UpdateCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(appUpdateServiceProvider);
    if (service == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.updatesTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(AppUpdateService.current.toString()),
              if (service.manifest != null)
                Text('${l.updateAvailable}: ${service.manifest!.version}'),
              Text(switch (service.status) {
                UpdateStatus.checking => l.updateChecking,
                UpdateStatus.wifi => l.updateWaitingWifi,
                UpdateStatus.downloading => l.updateDownloading,
                UpdateStatus.ready => l.updateReady,
                UpdateStatus.failed => l.updateFailed,
                UpdateStatus.installing => l.updateInstalling,
                _ => l.updateCheckHint,
              }),
              if (service.status == UpdateStatus.downloading)
                LinearProgressIndicator(value: service.progress),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.updateAutomatic),
                value: service.automatic,
                onChanged: service.setAutomatic,
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed:
                        service.status == UpdateStatus.checking ||
                            service.status == UpdateStatus.downloading ||
                            service.status == UpdateStatus.installing
                        ? null
                        : () => service.check(manual: true),
                    child: Text(l.updateCheck),
                  ),
                  if (service.package != null &&
                      const [
                        UpdateStatus.wifi,
                        UpdateStatus.available,
                        UpdateStatus.failed,
                      ].contains(service.status))
                    TextButton(
                      onPressed: () => service.download(allowMobile: true),
                      child: Text(l.updateDownloadNow),
                    ),
                  if (service.status == UpdateStatus.ready)
                    FilledButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(l.updateInstall),
                            content: Text(l.updateInstallConfirm),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(l.updateLater),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(l.updateInstall),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        service.installing();
                        try {
                          final helper = await UpdateInstaller.prepare(service);
                          final workspace = ref.read(vaultWorkspaceProvider);
                          final result = await UpdateInstaller.install(
                            service,
                            helper,
                            () async {
                              if (workspace == null) {
                                throw StateError('Workspace unavailable');
                              }
                              await workspace.closeForUpdate();
                            },
                          );
                          service.installationFailed();
                          if (result == 'permission' && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.updatePermission)),
                            );
                          }
                        } catch (_) {
                          service.installationFailed();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.updateFailed)),
                            );
                          }
                        }
                      },
                      child: Text(l.updateInstall),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

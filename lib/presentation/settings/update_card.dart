import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers/app_providers.dart';
import '../../infrastructure/updates/app_update_service.dart';
import '../../infrastructure/updates/update_installer.dart';
import '../../infrastructure/updates/windows_update_identity.dart';
import '../../l10n/app_localizations.dart';

final appUpdateServiceProvider = Provider<AppUpdateService?>((ref) => null);
final windowsUpdateRegistrationIssueProvider = Provider<bool>((ref) => false);

class UpdateCard extends ConsumerWidget {
  const UpdateCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(appUpdateServiceProvider);
    final l = AppLocalizations.of(context);
    const cancelledCodes = {'uac_cancelled', 'wizard_cancelled', 'cancelled'};
    if (service == null) {
      if (!ref.watch(windowsUpdateRegistrationIssueProvider)) {
        return const SizedBox.shrink();
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.updatesTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(l.windowsUpdateRegistrationIssue),
            ],
          ),
        ),
      );
    }
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
              if (service.platform == 'windows-installed' &&
                  !windowsInstalledUpdateEnabled &&
                  service.status == UpdateStatus.ready)
                Text(l.windowsUpdateManualInstallRequired),
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
                  if (service.status == UpdateStatus.ready &&
                      (service.platform != 'windows-installed' ||
                          windowsInstalledUpdateEnabled))
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
                          final workspace = ref.read(vaultWorkspaceProvider);
                          Future<void> closeWorkspace() async {
                            if (workspace == null) {
                              throw const WindowsUpdateCloseRefused();
                            }
                            if (workspace.busy) {
                              throw const WindowsUpdateCloseRefused();
                            }
                            await workspace.closeForUpdate();
                          }

                          final String result;
                          if (service.platform == 'windows-installed') {
                            final session =
                                await UpdateInstaller.prepareInstalled(service);
                            result = await UpdateInstaller.installInstalled(
                              session,
                              closeWorkspace,
                            );
                          } else {
                            final helper = await UpdateInstaller.prepare(
                              service,
                            );
                            result = await UpdateInstaller.install(
                              service,
                              helper,
                              closeWorkspace,
                            );
                          }
                          service.installationFailed(result);
                          if (context.mounted &&
                              (result == 'permission' ||
                                  cancelledCodes.contains(result))) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  result == 'permission'
                                      ? l.updatePermission
                                      : l.updateCancelled,
                                ),
                              ),
                            );
                          }
                        } catch (error) {
                          service.installationFailed(
                            error is WindowsInstalledUpdateException
                                ? error.code
                                : 'installation',
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error is WindowsInstalledUpdateException &&
                                          cancelledCodes.contains(error.code)
                                      ? l.updateCancelled
                                      : l.updateFailed,
                                ),
                              ),
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

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../infrastructure/portability/platform_file_publisher.dart';
import '../../infrastructure/portability/equis_backup_service.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/app_providers.dart';
import '../../l10n/app_localizations.dart';
import '../shared/equis_glass.dart';

class PortabilityScreen extends ConsumerStatefulWidget {
  const PortabilityScreen({super.key});

  @override
  ConsumerState<PortabilityScreen> createState() => _PortabilityScreenState();
}

class _PortabilityScreenState extends ConsumerState<PortabilityScreen> {
  bool _busy = false;
  Map<String, dynamic>? _lastBackup;
  final _publisher = PlatformFilePublisher();

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  Future<void> _loadLastBackup() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Exception {
      return;
    }
    final encoded = prefs.getString('last_portable_backup');
    if (encoded != null && mounted) {
      try {
        setState(
          () => _lastBackup = jsonDecode(encoded) as Map<String, dynamic>,
        );
      } on FormatException {
        /* Ignore damaged display metadata. */
      }
    }
  }

  Future<void> _validateLastBackup() async {
    final backup = _lastBackup;
    if (backup == null) return;
    final password = await _askPassword(confirm: false);
    if (password == null || !mounted) return;
    await _run(() async {
      final directory = await Directory(
        (await getTemporaryDirectory()).path,
      ).createTemp('equis-check-');
      try {
        final file = File('${directory.path}/backup.equis');
        await _publisher.read(backup['uri'] as String, file);
        await ref
            .read(localAppDependenciesProvider)!
            .backups
            .validate(source: file, password: password);
      } finally {
        await directory.delete(recursive: true);
      }
    }, AppLocalizations.of(context).backupValidMessage);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final vault = ref.watch(localFinanceControllerProvider).valueOrNull?.vault;
    final workspace = ref.watch(vaultWorkspaceProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.portabilityTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_lastBackup != null)
            ListTile(
              title: Text(l.lastBackupLabel),
              subtitle: Text(
                '${_lastBackup!['name']}\n${DateTime.parse(_lastBackup!['date'] as String).toLocal()}\n${_lastBackup!['location']}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.verified_outlined),
                tooltip: l.validateBackupAction,
                onPressed: _busy ? null : _validateLastBackup,
              ),
            ),
          EquisGlassCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(l.createEncryptedBackupAction),
                  subtitle: Text(l.encryptedBackupDescription),
                  enabled: !_busy && vault != null,
                  onTap: !_busy && vault != null
                      ? () => _createBackup(vault.id.value)
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(l.validateBackupAction),
                  subtitle: Text(l.validateBackupDescription),
                  enabled: !_busy,
                  onTap: _busy ? null : _validateBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text(l.restoreBackupAction),
                  subtitle: Text(
                    workspace != null
                        ? l.restoreAddsVaultMessage
                        : vault == null
                        ? l.restoreBackupDescription
                        : l.restoreRequiresCleanProfileMessage,
                  ),
                  enabled: !_busy && (workspace != null || vault == null),
                  onTap: !_busy && (workspace != null || vault == null)
                      ? _restoreBackup
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          EquisGlassCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.data_object),
                  title: Text(l.exportJsonAction),
                  subtitle: Text(l.plaintextExportDescription),
                  enabled: !_busy && vault != null,
                  onTap: !_busy && vault != null
                      ? () => _export(vault.id.value, json: true)
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: Text(l.exportCsvAction),
                  subtitle: Text(l.transactionCsvDescription),
                  enabled: !_busy && vault != null,
                  onTap: !_busy && vault != null
                      ? () => _export(vault.id.value, json: false)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup(String vaultId) async {
    final password = await _askPassword(confirm: true);
    if (password == null || !mounted) return;
    await _run(() async {
      final directory = await Directory(
        (await getTemporaryDirectory()).path,
      ).createTemp('equis-backup-');
      try {
        final name = 'equis-backup-${_stamp()}.equis';
        final file = File('${directory.path}/$name');
        final backups = ref.read(localAppDependenciesProvider)!.backups;
        await backups.create(
          vaultId: vaultId,
          password: password,
          destination: file,
        );
        await backups.validate(source: file, password: password);
        final saved = await _publisher.publish(
          file,
          name,
          'application/octet-stream',
        );
        if (saved == null) throw const _SaveCancelled();
        final metadata = <String, dynamic>{
          ...saved,
          'name': name,
          'date': DateTime.now().toUtc().toIso8601String(),
        };
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_portable_backup', jsonEncode(metadata));
        if (mounted) setState(() => _lastBackup = metadata);
      } finally {
        await directory.delete(recursive: true);
      }
    }, AppLocalizations.of(context).backupCreatedMessage);
  }

  Future<void> _validateBackup() async {
    final selection = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Equis backup', extensions: ['equis']),
      ],
    );
    if (selection == null || !mounted) return;
    final password = await _askPassword(confirm: false);
    if (password == null || !mounted) return;
    await _run(() async {
      await ref
          .read(localAppDependenciesProvider)!
          .backups
          .validate(source: File(selection.path), password: password);
    }, AppLocalizations.of(context).backupValidMessage);
  }

  Future<void> _restoreBackup() async {
    final selection = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Equis backup', extensions: ['equis']),
      ],
    );
    if (selection == null || !mounted) return;
    final password = await _askPassword(confirm: false);
    if (password == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).restoreBackupAction),
        content: Text(
          ref.read(vaultWorkspaceProvider) != null
              ? AppLocalizations.of(context).restoreAddsVaultMessage
              : AppLocalizations.of(context).restoreBackupConfirmation,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).restoreBackupAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final workspace = ref.read(vaultWorkspaceProvider);
      if (workspace != null) {
        await workspace.restoreBackup(File(selection.path), password);
      } else {
        await ref
            .read(localAppDependenciesProvider)!
            .backups
            .restore(source: File(selection.path), password: password);
        await ref.read(localFinanceControllerProvider.notifier).reload();
      }
    }, AppLocalizations.of(context).backupRestoredMessage);
  }

  Future<void> _export(String vaultId, {required bool json}) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.plaintextPrivacyWarningTitle),
        content: Text(l.plaintextPrivacyWarningBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const Key('confirm-plaintext-export'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.continueExportAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final extension = json ? 'json' : 'csv';
    await _run(() async {
      final directory = await Directory(
        (await getTemporaryDirectory()).path,
      ).createTemp('equis-export-');
      try {
        final name =
            'equis-${json ? 'vault' : 'transactions'}-${_stamp()}.$extension';
        final file = File('${directory.path}/$name');
        final exporter = ref
            .read(localAppDependenciesProvider)!
            .plaintextExports;
        if (json) {
          await exporter.exportJson(vaultId: vaultId, destination: file);
        } else {
          await exporter.exportTransactionsCsv(
            vaultId: vaultId,
            destination: file,
          );
        }
        if (await _publisher.publish(
              file,
              name,
              json ? 'application/json' : 'text/csv',
            ) ==
            null) {
          throw const _SaveCancelled();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    }, l.exportCompletedMessage);
  }

  Future<String?> _askPassword({required bool confirm}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(AppLocalizations.of(context).backupPasswordTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('backup-password'),
                controller: first,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).passwordLabel,
                  errorText: error,
                ),
              ),
              if (confirm) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('backup-password-confirmation'),
                  controller: second,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    ).confirmPasswordLabel,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.isEmpty ||
                    (confirm &&
                        (first.text.length < 12 ||
                            first.text != second.text))) {
                  setState(() {
                    error = AppLocalizations.of(
                      context,
                    ).backupPasswordValidationMessage;
                  });
                  return;
                }
                Navigator.pop(context, first.text);
              },
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } on _SaveCancelled {
      // The native document picker was dismissed.
    } on LegacyBackupNeedsMigration {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.legacyBackupUnsupportedMessage)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).portabilityErrorMessage),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _stamp() {
  final now = DateTime.now().toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}-${now.microsecond}';
}

class _SaveCancelled implements Exception {
  const _SaveCancelled();
}

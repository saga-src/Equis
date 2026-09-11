import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:drift/drift.dart' show Variable;
import '../domain/shared/uuid_v7.dart';
import '../domain/shared/utc_instant.dart';
import '../infrastructure/cloud/supabase_cloud_auth_gateway.dart';
import '../infrastructure/security/vault_identity.dart';
import '../infrastructure/security/secure_string_store.dart';
import '../application/services/sync_engine.dart';
import 'providers/local_app_dependencies.dart';

final class LocalVaultEntry {
  LocalVaultEntry({
    required this.profileId,
    this.vaultId,
    this.name = '',
    this.legacy = false,
  });
  final String profileId;
  String? vaultId;
  String name;
  final bool legacy;
  Map<String, Object?> toJson() => {
    'profile': profileId,
    'vault': vaultId,
    'name': name,
    'legacy': legacy,
  };
  factory LocalVaultEntry.fromJson(Map<String, dynamic> value) {
    final id = value['profile'] as String;
    if (id != 'legacy') EntityId.parse(id);
    return LocalVaultEntry(
      profileId: id,
      vaultId: value['vault'] as String?,
      name: value['name'] as String? ?? '',
      legacy: id == 'legacy',
    );
  }
}

final class VaultWorkspace extends ChangeNotifier {
  VaultWorkspace._(this.root, {this.storage, this.cloudEnabled = true});
  final SecureStringStore? storage;
  final bool cloudEnabled;
  Future<void> Function()? awaitScopeDisposal;
  final Directory root;
  final List<LocalVaultEntry> entries = [];
  LocalAppDependencies? active;
  LocalVaultEntry? selected;
  bool busy = false;
  Future<void> closeForUpdate() async {
    if (busy) throw StateError('Vault operation already running');
    busy = true;
    notifyListeners();
    await active?.syncCoordinator?.stop();
    await active?.lifecycle.database.drainForUpdate();
    await active?.close();
  }

  int generation = 0;
  bool get legacy => selected?.legacy ?? false;
  File get _catalog => File('${root.path}/vault-catalog.json');
  Directory _directory(LocalVaultEntry entry) => entry.legacy
      ? root
      : Directory('${root.path}/profiles/${entry.profileId}');

  static Future<VaultWorkspace> open({
    Directory? rootDirectory,
    SecureStringStore? storage,
    bool cloudEnabled = true,
  }) async {
    final support = rootDirectory ?? await getApplicationSupportDirectory();
    final workspace = VaultWorkspace._(
      rootDirectory ?? Directory('${support.path}/Equis'),
      storage: storage,
      cloudEnabled: cloudEnabled,
    );
    await workspace.root.create(recursive: true);
    String? selectedId;
    if (await workspace._catalog.exists()) {
      final json = jsonDecode(await workspace._catalog.readAsString()) as Map;
      if (json['version'] != 2) {
        throw const FormatException('Unsupported vault catalog');
      }
      workspace.entries.addAll(
        (json['entries'] as List).map(
          (value) =>
              LocalVaultEntry.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      );
      selectedId = json['active'] as String?;
    } else if (await File('${workspace.root.path}/vault.db').exists()) {
      workspace.entries.add(
        LocalVaultEntry(profileId: 'legacy', name: 'Legacy', legacy: true),
      );
    }
    if (workspace.entries.isEmpty) {
      workspace.entries.add(
        LocalVaultEntry(profileId: EntityId.generate().value),
      );
    }
    final entry =
        workspace.entries.where((e) => e.profileId == selectedId).firstOrNull ??
        workspace.entries.first;
    workspace.active = await workspace._openEntry(entry);
    workspace.selected = entry;
    await workspace.refresh();
    return workspace;
  }

  Future<LocalAppDependencies> _openEntry(LocalVaultEntry entry) =>
      LocalAppDependencies.bootstrap(
        profileDirectory: _directory(entry),
        profileId: entry.legacy ? null : entry.profileId,
        storage: storage,
        cloudEnabled: cloudEnabled,
      );

  Future<void> refresh() async {
    final snapshot = await active?.session.load();
    selected?.vaultId = snapshot?.vault?.id.value;
    selected?.name = snapshot?.vault?.name ?? '';
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final temporary = File('${_catalog.path}.part');
    await temporary.writeAsString(
      jsonEncode({
        'version': 2,
        'active': selected?.profileId,
        'entries': entries.map((e) => e.toJson()).toList(),
      }),
      flush: true,
    );
    // Windows rename-over-existing is supported by Dart's file implementation.
    await temporary.rename(_catalog.path);
  }

  Future<void> _exclusive(Future<void> Function() action) async {
    if (busy) throw StateError('Vault operation already running');
    busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> select(LocalVaultEntry entry) => _exclusive(() async {
    if (selected?.profileId == entry.profileId) return;
    final candidate = await _openEntry(entry);
    await _activate(entry, candidate);
  });

  Future<void> create() => _exclusive(() async {
    final entry = LocalVaultEntry(profileId: EntityId.generate().value);
    final candidate = await _openEntry(entry);
    entries.add(entry);
    try {
      await _activate(entry, candidate);
    } catch (_) {
      if (active != candidate) await _discardStage(entry, candidate);
      rethrow;
    }
  });

  Future<void> _discardStage(
    LocalVaultEntry entry,
    LocalAppDependencies candidate,
  ) async {
    if (entry.legacy || entry == selected) {
      throw StateError('Cannot discard active vault');
    }
    await candidate.close();
    entries.remove(entry);
    final directory = _directory(entry);
    final profiles = path.normalize(path.absolute('${root.path}/profiles'));
    final target = path.normalize(path.absolute(directory.path));
    if (!path.isWithin(profiles, target)) {
      throw StateError('Invalid staging directory');
    }
    if (await directory.exists()) await directory.delete(recursive: true);
    final store = storage ?? const FlutterSecureStringStore();
    await store.delete(
      'equis.profiles.${entry.profileId}.vault.equis.vault.identity',
    );
    await store.delete(
      'equis.profiles.${entry.profileId}.database.equis.vault_master_key.v1',
    );
  }

  Future<void> _activate(
    LocalVaultEntry entry,
    LocalAppDependencies candidate,
  ) async {
    final previous = active;
    final previousEntry = selected;
    final snapshot = await candidate.session.load();
    entry.vaultId = snapshot.vault?.id.value;
    entry.name = snapshot.vault?.name ?? '';
    await previous?.syncCoordinator?.stop();
    selected = entry;
    try {
      await _save();
    } catch (_) {
      selected = previousEntry;
      rethrow;
    }
    active = candidate;
    generation++;
    notifyListeners();
    // Consumers of the old scope are removed before its database is closed.
    await awaitScopeDisposal?.call();
    await previous?.close();
  }

  Future<void> restoreBackup(
    File file,
    String password,
  ) => _exclusive(() async {
    final identity = await active!.backups.inspectIdentity(
      source: file,
      password: password,
    );
    await refresh();
    final duplicate = entries
        .where((e) => e.vaultId == identity.vaultId && !e.legacy)
        .firstOrNull;
    if (duplicate != null) {
      final candidate = duplicate == selected
          ? active!
          : await _openEntry(duplicate);
      final same =
          await (await candidate.vaultKeys.requireVault(
            identity.vaultId,
          )).fingerprint() ==
          await identity.fingerprint();
      if (!same) {
        if (candidate != active) await candidate.close();
        throw StateError('Vault identity mismatch');
      }
      if (candidate != active) await _activate(duplicate, candidate);
      return;
    }
    final entry = LocalVaultEntry(
      profileId: EntityId.generate().value,
      vaultId: identity.vaultId,
    );
    final candidate = await _openEntry(entry);
    try {
      await candidate.backups.restore(source: file, password: password);
      if (identity.ownerId != null) {
        await candidate.lifecycle.database.customStatement(
          'INSERT INTO vault_cloud_bindings (vault_id, auth_user_id, sync_enabled, linked_at) VALUES (?, ?, 0, ?)',
          [
            identity.vaultId,
            identity.ownerId,
            DateTime.now().toUtc().microsecondsSinceEpoch,
          ],
        );
      }
      await candidate.lifecycle.database.verifyIntegrity();
      entries.add(entry);
      await _activate(entry, candidate);
    } catch (_) {
      if (active != candidate) await _discardStage(entry, candidate);
      rethrow;
    }
  });

  Future<List<Map<String, dynamic>>> discover() async {
    final auth = active!.cloudAccounts.auth;
    if (auth is! SupabaseCloudAuthGateway || auth.currentIdentity == null) {
      return [];
    }
    return auth.client
        .from('vaults')
        .select('id,created_at,owner_id,key_fingerprint')
        .eq('owner_id', auth.currentIdentity!.authUserId)
        .order('created_at');
  }

  Future<void> restoreCloud(
    Map<String, dynamic> descriptor,
    String key,
  ) => _exclusive(() async {
    final auth = active!.cloudAccounts.auth;
    if (auth is! SupabaseCloudAuthGateway ||
        auth.currentIdentity?.authUserId != descriptor['owner_id']) {
      throw StateError('Owner account required');
    }
    final identity = VaultIdentity.fromKey(
      key,
      ownerId: auth.currentIdentity!.authUserId,
    );
    if (identity.vaultId != descriptor['id'] ||
        await identity.fingerprint() != descriptor['key_fingerprint']) {
      throw const FormatException('Vault key mismatch');
    }
    await refresh();
    final duplicate = entries
        .where((e) => e.vaultId == identity.vaultId && !e.legacy)
        .firstOrNull;
    if (duplicate != null) {
      final candidate = duplicate == selected
          ? active!
          : await _openEntry(duplicate);
      if (await (await candidate.vaultKeys.requireVault(
            identity.vaultId,
          )).fingerprint() !=
          await identity.fingerprint()) {
        if (candidate != active) await candidate.close();
        throw const FormatException('Vault key mismatch');
      }
      if (candidate != active) await _activate(duplicate, candidate);
      return;
    }
    final entry = LocalVaultEntry(
      profileId: EntityId.generate().value,
      vaultId: identity.vaultId,
    );
    final candidate = await _openEntry(entry);
    try {
      await candidate.vaultKeys.installVaultIdentity(identity);
      final deviceId = EntityId.generate().value;
      // Pull-only staging prevents publishing placeholder rows.
      await candidate.lifecycle.database.customStatement(
        "INSERT INTO currencies (code,name_key,symbol,minor_units) VALUES ('BRL','currency.brl','R\$',2)",
      );
      await candidate.lifecycle.database.customStatement(
        "INSERT INTO currencies (code,name_key,symbol,minor_units) VALUES ('USD','currency.usd','\$',2)",
      );
      final now = UtcInstant.now().epochMicroseconds;
      await candidate.lifecycle.database.customStatement(
        "INSERT INTO vaults(id,name,base_currency_code,locale,timezone,created_at,updated_at) VALUES (?,'Equis','BRL','en-US','UTC',?,?)",
        [identity.vaultId, now, now],
      );
      await candidate.lifecycle.database.customStatement(
        "INSERT INTO devices(id,vault_id,name,platform,created_at,last_seen_at) VALUES (?,?,'Equis',?,?,?)",
        [
          deviceId,
          identity.vaultId,
          Platform.isAndroid ? 'android' : 'windows',
          now,
          now,
        ],
      );
      await candidate.lifecycle.database.customStatement(
        'INSERT INTO vault_cloud_bindings(vault_id,auth_user_id,sync_enabled,linked_at) VALUES (?,?,0,?)',
        [identity.vaultId, identity.ownerId, now],
      );
      final result = await candidate.sync!.synchronize(
        vaultId: identity.vaultId,
        deviceId: deviceId,
      );
      if (result.status != SyncRunStatus.succeeded ||
          result.pulled == 0 ||
          result.conflicts != 0) {
        throw StateError('Cloud restoration incomplete');
      }
      final restoredRoot = await candidate.lifecycle.database
          .customSelect(
            "SELECT record_id FROM sync_entity_state WHERE entity_type='vault' "
            "AND record_id=? AND last_synced_revision IS NOT NULL",
            variables: [Variable(identity.vaultId)],
          )
          .getSingleOrNull();
      if (restoredRoot == null) throw StateError('Cloud vault root missing');
      await candidate.lifecycle.database.verifyIntegrity();
      await candidate.lifecycle.database.customStatement(
        'UPDATE vault_cloud_bindings SET sync_enabled=1 WHERE vault_id=?',
        [identity.vaultId],
      );
      entries.add(entry);
      await _activate(entry, candidate);
    } catch (_) {
      if (active != candidate) await _discardStage(entry, candidate);
      rethrow;
    }
  });
}
